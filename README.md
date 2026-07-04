# RISC-V 5-Stage Pipelined Processor

This repository contains a fully functional, 5-stage pipelined RISC-V processor written from scratch in Verilog. The processor implements the RV32I base integer instruction set and has been extended with advanced hardware features including dynamic branch prediction, a hardware multiplier/divider (RV32M), CSR exception handling, and a synchronous L1 cache.

The design has been converted into a **System-on-Chip (SoC)** capable of printing characters to a UART console and reading a hardware clock. It is verified using a **C++ Instruction-Set Simulator (ISS) Co-Simulation** framework that checks every architectural state change against a golden reference model.

---

## Table of Contents

1. [What Is a Processor? The Big Idea](#1-what-is-a-processor-the-big-idea)
2. [The 5-Stage Pipeline — Assembly Line for Instructions](#2-the-5-stage-pipeline--assembly-line-for-instructions)
3. [Every Verilog File Explained](#3-every-verilog-file-explained)
4. [How the Files Wire Together Into a CPU](#4-how-the-files-wire-together-into-a-cpu)
5. [Running the Simulation](#5-running-the-simulation)
6. [Viewing Waveforms in Surfer](#6-viewing-waveforms-in-surfer)
7. [Advanced Upgrades](#7-advanced-upgrades)
8. [System-on-Chip (SoC) Mode](#8-system-on-chip-soc-mode)
9. [C++ Co-Simulation Verification](#9-c-co-simulation-verification)
10. [Bug Fixes Applied to This Codebase](#10-bug-fixes-applied-to-this-codebase)

---

## 1. What Is a Processor? The Big Idea

A processor (CPU) is fundamentally just a machine that reads an instruction from memory, figures out what that instruction wants to do, does it, and then repeats — billions of times per second. There are only three things a processor ever really does:

- **Arithmetic & Logic:** Add two numbers, compare them, shift bits.
- **Memory Access:** Load a value from RAM, store a result back to RAM.
- **Control Flow:** Jump to a different instruction (branching, function calls).

All of that complexity in modern chips comes from doing these things *faster and smarter*, not from doing anything fundamentally different.

The instructions themselves are just 32-bit binary numbers sitting in memory. The top 7 bits (called the **opcode**) tell the processor what kind of instruction it is. The remaining 25 bits describe which registers and values to operate on. The RISC-V instruction set defines exactly which bit patterns mean which operations — this is the **ISA (Instruction Set Architecture)**.

```
A RISC-V instruction (32 bits wide):
 31       25 24  20 19  15 14 12 11   7 6     0
┌──────────┬──────┬──────┬─────┬──────┬───────┐
│  funct7  │  rs2 │  rs1 │ fn3 │  rd  │opcode │  ← R-type (e.g. ADD)
└──────────┴──────┴──────┴─────┴──────┴───────┘
         rs2/rs1 = source registers (which numbers to read)
         rd      = destination register (where to write the result)
         opcode  = what to do (add, load, branch, etc.)
```

The processor has 32 general-purpose registers (x0 through x31), each 32 bits wide. They are its "scratch space" for live calculations. x0 is hardwired to zero.

---

## 2. The 5-Stage Pipeline — Assembly Line for Instructions

A single instruction takes multiple steps to complete: fetch it, decode it, do the math, touch memory, and write back the result. Rather than waiting for one instruction to finish before starting the next, a pipelined processor overlaps them — like an assembly line where each worker handles one step.

```
Clock Cycle →     1       2       3       4       5       6       7
                ┌─────┐
Instruction 1   │ IF  │──►│ ID  │──►│ EX  │──►│ MEM │──►│ WB  │
                └─────┘   └─────┘   └─────┘   └─────┘   └─────┘
                          ┌─────┐
Instruction 2             │ IF  │──►│ ID  │──►│ EX  │──►│ MEM │──►│ WB  │
                          └─────┘   └─────┘   └─────┘   └─────┘   └─────┘
                                    ┌─────┐
Instruction 3                       │ IF  │──►│ ID  │──►│ EX  │──►│ MEM │──►│ WB  │
                                    └─────┘
```

By cycle 5, all 5 stages are busy with different instructions simultaneously. This is why a 5-stage pipeline can deliver roughly **5× throughput** compared to a single-cycle design.

The five stages are:

| Stage | Name | What Happens |
|---|---|---|
| **IF** | Instruction Fetch | Read the next instruction from instruction memory using the current Program Counter (PC). |
| **ID** | Instruction Decode | Crack open the 32-bit instruction, figure out what it means, read register values, generate immediates. |
| **EX** | Execute | Run the ALU (arithmetic logic unit) to compute the result, or calculate a memory address. |
| **MEM** | Memory Access | Read from or write to data RAM (for `lw`/`sw` instructions). |
| **WB** | Write Back | Write the final result back into the destination register. |

Between each stage sits a **pipeline register** — a set of flip-flops that snapshot all the signals at the end of each clock cycle and hand them to the next stage. This is what lets the stages run simultaneously.

---

## 3. Every Verilog File Explained

Here is every source file in this project, what it does, and exactly where it fits in the CPU.

---

### 🔵 The Top Level

#### [`top.v`](top.v)
This is the **master wiring harness** of the entire CPU. It does not implement any logic itself — it instantiates every other module and connects them together with wires. Every signal that flows between stages (like `pc_current`, `id_instr`, `ex_alu_result`, `mem_rd`, `stall_pc`) is declared and routed here.

When you want to understand how two modules talk to each other, this is the file to read.

**Notable signals in `top.v`:**
- `pc_next` — the computed next PC value (from trap/mispredict/stall/increment logic)
- `stall_pc`, `stall_if_id`, etc. — stall signals that freeze pipeline stages
- `flush_if_id`, `flush_id_ex` — flush signals that inject NOP bubbles
- `mem_forward_data` — the correct forwarded value from the MEM stage (either a load result or ALU result)

---

### 🟢 IF Stage — Instruction Fetch

#### [`pc.v`](pc.v)
The **Program Counter** is the simplest module in the entire design — it is just a 32-bit register that holds the address of the current instruction. On every clock edge, it loads whatever `pc_next` is. If `stall_pc` is high (pipeline is frozen), it holds its value and does not advance.

```
Every clock edge:  pc_current <= pc_next
```

#### [`instr_mem.v`](instr_mem.v)
The **Instruction Memory** is a read-only Block ROM. The processor loads a `.hex` file into it at simulation start. Given the current PC, it returns the 32-bit instruction at that address. It is synchronous — the output appears one clock cycle after the address is presented (matching the clocked cache timing model).

#### [`branch_predictor.v`](branch_predictor.v)
Sits inside the IF stage and looks up the current PC in a **Branch History Table (BHT)** and **Branch Target Buffer (BTB)** before the instruction is even decoded. If a branch at this address was taken last time, the predictor immediately redirects the PC to the remembered target — giving a **0-cycle branch penalty** on correctly predicted branches. Mispredictions are corrected one cycle later in the ID stage.

---

### 🟡 ID Stage — Instruction Decode

#### [`if_id_reg.v`](if_id_reg.v)
The **IF/ID pipeline register** latches `{pc, instruction}` from the Fetch stage and holds it stable while the Decode stage works on it. On a flush (branch mispredict or trap), it is cleared to a NOP (`0x00000013`). On a stall, it holds its current value.

#### [`control.v`](control.v)
The **Control Unit** is the brain of the decode stage. It reads the 7-bit `opcode` (bits 6:0 of the instruction) and generates a set of 1-bit and 2-bit control signals that tell every downstream stage what to do:

| Signal | Meaning |
|---|---|
| `RegWrite` | 1 = write a result into a destination register at WB |
| `MemRead` | 1 = this is a `lw` — read from data memory |
| `MemWrite` | 1 = this is a `sw` — write to data memory |
| `MemToReg` | 1 = write memory data to rd; 0 = write ALU result |
| `ALUSrc` | 1 = second ALU operand is an immediate; 0 = a register |
| `Branch` | 1 = this is a conditional branch instruction |
| `Jump` | 1 = this is a `jal` or `jalr` |
| `ALUOp` | 2-bit code telling `alu_control.v` what operation to perform |

Supported opcodes in `control.v`: `R_TYPE`, `I_ARITH`, `LOAD`, `STORE`, `BRANCH`, `JAL`, `JALR`, `SYSTEM` (CSR/ecall), `LUI`, `AUIPC`.

#### [`reg_file.v`](reg_file.v)
The **Register File** holds all 32 general-purpose RISC-V registers (x0–x31). It has two asynchronous read ports (returning `rs1` and `rs2` in the same cycle they are requested) and one synchronous write port (writing on the rising clock edge at WB). x0 is permanently wired to zero — any write to it is silently ignored.

**Write-First Forwarding:** If the WB stage is writing to the same register being read by ID in the same cycle, the register file bypasses the write data directly to the read output, avoiding a one-cycle stale-value issue.

#### [`imm_gen.v`](imm_gen.v)
The **Immediate Generator** extracts the constant embedded inside the instruction and sign-extends it to 32 bits. Different instruction formats scatter the immediate bits across different fields, so this module reassembles them:

- **I-type** (`addi`, `lw`, `jalr`): bits `[31:20]`
- **S-type** (`sw`): bits `[31:25]` and `[11:7]`
- **B-type** (branches): bits scattered, always even (LSB = 0)
- **J-type** (`jal`): bits scattered, always even (LSB = 0)
- **U-type** (`lui`, `auipc`): bits `[31:12]`, lower 12 bits = 0

---

### 🔴 EX Stage — Execute

#### [`id_ex_reg.v`](id_ex_reg.v)
The **ID/EX pipeline register** transfers all decoded signals and register values from the ID stage into the EX stage: `{pc, rs1_val, rs2_val, immediate, rd, RegWrite, MemRead, MemWrite, MemToReg, ALUSrc, ALUOp, ALUCtrl, Branch, Jump, funct3, funct7, opcode, csr_addr, csr_op, csr_sel}`.

#### [`alu_control.v`](alu_control.v)
The **ALU Control** takes the 2-bit `ALUOp` from the control unit and the `funct3`/`funct7` fields from the instruction, and maps them to a specific 4-bit operation code that the ALU understands. For example, an R-type instruction with `funct3=000` and `funct7=0000000` maps to ADD, while `funct7=0100000` maps to SUB.

#### [`alu.v`](alu.v)
The **Arithmetic Logic Unit** is the computational core of the processor. It takes two 32-bit operands (`a` and `b`) and a 4-bit control code, and produces a 32-bit result and a zero flag. Supported operations:

```
ADD, SUB, AND, OR, XOR, SLL (shift left), SRL (shift right logical),
SRA (shift right arithmetic), SLT (set less than signed),
SLTU (set less than unsigned)
```

#### [`mult_div.v`](mult_div.v)
The **Multiplier/Divider** handles the RV32M extension instructions. It implements all 8 multiply and divide variants: `MUL`, `MULH`, `MULHU`, `MULHSU`, `DIV`, `DIVU`, `REM`, `REMU`. This is purely combinational — results are available within the same clock cycle as inputs.

#### [`forwarding_unit.v`](forwarding_unit.v)
The **Forwarding Unit** solves a critical correctness problem in pipelining: when an instruction produces a result that the very next instruction needs, the result has not been written to the register file yet (it is still in flight through the pipeline). The forwarding unit detects this and routes the result directly from the MEM or WB stage back to the EX stage's ALU inputs, bypassing the stale register file value.

```
ForwardA/B encoding:
  2'b00 → use register file value (no hazard)
  2'b10 → forward ALU result from MEM stage  (newer)
  2'b01 → forward write-back value from WB   (older)
```

---

### 🟣 MEM Stage — Memory Access

#### [`ex_mem_reg.v`](ex_mem_reg.v)
The **EX/MEM pipeline register** transfers all execute-stage outputs into the memory stage: `{alu_result, rs2_val, rd, RegWrite, MemRead, MemWrite, MemToReg, Jump, zero, branch_target, pc_plus4, funct3, csr signals}`.

#### [`data_mem.v`](data_mem.v)
The **Data Memory** is a synchronous Block RAM storing 64 words (256 bytes). Writes happen on the clock edge. Reads also happen synchronously on the clock edge (matching the timing expected by the cache controller). This is the backing store for the L1 Data Cache.

#### [`cache_controller.v`](cache_controller.v)
The **L1 Cache Controller** implements a direct-mapped, write-through cache with 8 entries. On every data access:
- **Cache Hit:** Data is returned immediately from the cache array — no stall.
- **Cache Miss:** The controller asserts `cpu_stall` high and enters a 4-cycle wait state (`WAIT0→WAIT1→WAIT2→WAIT3→FILL`) while fetching from main memory, then delivers the data to the CPU.

Addresses in MMIO space (`>= 0x00002000`) entirely bypass this cache to prevent volatile peripheral values from being cached.

---

### ⚪ WB Stage — Write Back

#### [`mem_wb_reg.v`](mem_wb_reg.v)
The **MEM/WB pipeline register** transfers the final result (either from memory read or ALU) to the write-back stage: `{alu_result, mem_read_data, rd, RegWrite, MemToReg, Jump, pc_plus4}`.

The WB stage itself has no dedicated module — the mux that selects between `mem_read_data` and `alu_result` and the write-back connection to `reg_file.v` are wired directly in `top.v`.

---

### ⚙️ Hazard Detection

#### [`hazard_unit.v`](hazard_unit.v)
The **Hazard Detection Unit** monitors the pipeline for situations where instructions cannot proceed correctly and need to be stalled or flushed:

1. **Load-Use Hazard:** When a `lw` is in EX and the very next instruction in ID needs that loaded value, the loaded data will not be available until after MEM. The hazard unit freezes the PC and IF/ID register for 1 cycle and inserts a NOP bubble into EX, giving the load time to complete.

2. **Branch/JALR Stall:** Since branches resolve in the ID stage, if a branch's operands are being produced by an instruction still in EX or MEM, the hazard unit stalls the pipeline until those values are available.

3. **Cache Stalls:** If either the instruction cache (`icache_stall`) or data cache (`dcache_stall`) signals a miss, the entire pipeline is frozen until the miss is resolved.

4. **CSR Immediate Optimization:** Instructions like `csrrwi` use a 5-bit immediate in the `rs1` field rather than an actual register. The hazard unit recognizes these and skips the unnecessary register hazard check.

#### [`csr_file.v`](csr_file.v)
The **CSR (Control and Status Register) File** manages privileged machine-mode state:

| CSR | Address | Purpose |
|---|---|---|
| `mstatus` | `0x300` | Machine status flags (interrupt enable, privilege mode) |
| `mtvec` | `0x305` | Trap vector — address to jump to on ecall/exception |
| `mepc` | `0x341` | Machine exception PC — address of the faulting instruction |
| `mcause` | `0x342` | Cause code for the exception (11 = ecall from M-mode) |
| `mcycle` | `0xB00` | Clock cycle counter — increments every cycle |
| `minstret` | `0xB02` | Retired instruction counter |

When an `ecall` is decoded in the ID stage, the control unit asserts `trap_en`. The CSR file latches `mepc` and `mcause`, and `top.v` overrides the PC with `mtvec`, flushing all in-flight instructions.

---

## 4. How the Files Wire Together Into a CPU

Here is the complete data and control flow through the processor, showing exactly which file hands off to which:

```
                              ┌─────────────────────────────────────────────────────────┐
                              │                     top.v (wiring hub)                   │
                              └─────────────────────────────────────────────────────────┘

[IF STAGE]
  pc.v                      ←── pc_next from top.v (trap/mispredict/stall/+4 mux)
    │ pc_current
    ▼
  branch_predictor.v        ←── fetch_pc (current PC)
    │ pred_taken, pred_target
    ▼
  instr_mem.v (via icache)  ←── pc_current (address)
    │ if_instr
    ▼
  if_id_reg.v               latches {pc, instr, pred_taken, pred_target}
    │
    ▼ (id_pc, id_instr)
─────────────────────────────────────────────────────────────────────────
[ID STAGE]
  control.v                 ←── id_instr[6:0] (opcode), funct3, funct12
    │ RegWrite, MemRead, MemWrite, ALUSrc, ALUOp, Branch, Jump, trap_en...

  reg_file.v                ←── id_rs1, id_rs2 (register addresses)
    │ id_read_data1, id_read_data2

  imm_gen.v                 ←── id_instr (full instruction)
    │ id_imm (sign-extended immediate)

  hazard_unit.v             ←── id_opcode, id_funct3, id_rs1, id_rs2,
    │                            ex_MemRead, ex_rd, mem_MemRead, mem_rd,
    │                            icache_stall, dcache_stall, trap_en, id_mispredict
    │ stall_pc, flush_if_id, flush_id_ex...

  Branch comparison in      ←── id_val1, id_val2 (forwarded register values)
  top.v                          id_mispredict, id_mispredict_target
    │
    ▼
  id_ex_reg.v               latches all decoded signals + reg values
    │
    ▼ (ex_*)
─────────────────────────────────────────────────────────────────────────
[EX STAGE]
  forwarding_unit.v         ←── ex_rs1, ex_rs2, mem_rd, wb_rd
    │ ForwardA, ForwardB

  alu_control.v             ←── ex_ALUOp, ex_funct3, ex_funct7
    │ ex_ALUCtrl

  alu.v                     ←── ex_alu_a (fwd mux + LUI/AUIPC select),
    │                            ex_alu_b (fwd mux or immediate)
    │ alu_result_raw, ex_zero

  mult_div.v                ←── ex_fwd_a, ex_fwd_b, ex_funct3, ex_funct7_5, ex_is_mul_div
    │ mult_div_result

    ▼ (final EX result = alu or mult_div, selected in top.v)
  ex_mem_reg.v              latches {alu_result, write_data, rd, control signals}
    │
    ▼ (mem_*)
─────────────────────────────────────────────────────────────────────────
[MEM STAGE]
  cache_controller.v        ←── mem_MemRead/Write, mem_alu_result (address),
  (u_dcache)                     mem_write_data, is_mmio gate
    │ dcache_stall, mem_read_data (from cache or fill)

  data_mem.v                ←── dmem_read, dmem_write, dmem_addr, dmem_wdata
    │ dmem_rdata

  MMIO decode in top.v      ←── mem_alu_result >= 0x2000 → timer or UART
    │ final_mem_read_data (= mmio_rdata OR cache data)
    │ mem_forward_data (= final_mem_read_data if load, else alu_result)

  csr_file.v                ←── csr_addr, csr_wdata, csr_op, trap_en, trap_pc, trap_cause
    │ mtvec_out, csr_rdata
    │
    ▼
  mem_wb_reg.v              latches {alu_result, mem_read_data, rd, RegWrite, MemToReg}
    │
    ▼ (wb_*)
─────────────────────────────────────────────────────────────────────────
[WB STAGE]  (no dedicated module, wired in top.v)
  wb_write_data  = wb_Jump     ? wb_pc_plus4    :
                   wb_MemToReg ? wb_read_data    :
                   wb_csr_sel  ? csr_rdata       :
                                 wb_alu_result

  reg_file.v.write_data ←── wb_write_data
  reg_file.v.write_addr ←── wb_rd
  reg_file.v.RegWrite   ←── wb_RegWrite
```

---

## 5. Running the Simulation

### Prerequisites
```bash
# Install Icarus Verilog
brew install icarus-verilog     # macOS
sudo apt install iverilog       # Ubuntu/Debian

# For ISS co-simulation
# Python 3 and a C++ compiler (g++) are required — both come with most systems
```

### Run Everything at Once (Recommended)
```bash
./verify.sh
```
This runs all 6 verification phases sequentially and reports pass/fail for each.

### Run Individual Testbenches
```bash
# Basic pipeline functionality
iverilog -s tb_top -o sim_top tb_top.v && ./sim_top

# Hazard detection & branch squash verification
iverilog -s tb_top_hazard -o sim_hazard tb_top_hazard.v && ./sim_hazard

# RV32M, CSR, Cache, Branch Predictor isolated tests
iverilog -s tb_upgrades -o sim_upgrades tb_upgrades.v && ./sim_upgrades

# SoC UART + Timer test
iverilog -s tb_soc -o sim_soc tb_soc.v && ./sim_soc

# Full comprehensive test (all features together)
iverilog -s tb_all -o sim_all tb_all.v && ./sim_all

# C++ co-simulation trace verification
python3 compare.py
```

---

## 6. Viewing Waveforms in Surfer

All testbenches dump a `.vcd` waveform file. You can inspect every single pipeline signal visually.

**Step 1 — Generate a Waveform:**
```bash
iverilog -s tb_all -o sim_all tb_all.v && ./sim_all
# Creates: tb_all.vcd
```

**Step 2 — Open Surfer:**
Go to **[surfer.app](https://surfer.app/)** in your browser.

**Step 3 — Load and Explore:**
Drag and drop `tb_all.vcd` onto the page. In the left panel, expand `tb_all → u_dut` and drag signals onto the timeline. Useful signals to watch:

| Signal Path | What to Look For |
|---|---|
| `u_dut.pc_current` | PC advancing every cycle |
| `u_dut.stall_pc` | Goes high during load-use hazard or cache miss |
| `u_dut.flush_if_id` | Goes high when branch mispredicted or trap fires |
| `u_dut.u_dcache.state` | 0=IDLE, 1-4=WAIT, 5=FILL (watch cache miss handling) |
| `u_dut.u_bp.bht[*]` | Branch history bits updating after each branch |
| `u_dut.u_regfile.regs[*]` | Register values accumulating over time |
| `u_dut.u_csr.mcycle` | Cycle counter incrementing every clock |

---

## 7. Advanced Upgrades

This processor was progressively upgraded beyond a basic RV32I implementation. Each upgrade adds a dedicated module.

### Dynamic Branch Prediction — [`branch_predictor.v`](branch_predictor.v)

**The problem without it:** Every branch requires the processor to wait until the ID stage to resolve the outcome, wasting 1 cycle. On a loop that runs 1000 times, that is 1000 wasted cycles.

**How this module solves it:** The predictor maintains an 8-entry Branch History Table (BHT) — one bit per entry saying "was this branch taken last time?" — and a Branch Target Buffer (BTB) mapping PC addresses to their target addresses. In the IF stage, before the instruction is even decoded, the BTB is checked. If the prediction says "taken," the PC immediately jumps to the cached target. If the prediction was wrong (resolved in ID), a 1-cycle flush happens.

**Effect:** Correctly predicted branches cost **0 cycles**. Mispredicted branches cost **1 cycle**. Without this, every taken branch costs 1 cycle regardless.

### RV32M Multiplier/Divider — [`mult_div.v`](mult_div.v)

**The problem without it:** Multiplication and division are not in the base RV32I ISA. Without hardware support, software must implement them using repeated additions/subtractions — potentially hundreds of cycles per operation.

**How this module solves it:** A fully combinational hardware multiplier and divider. Results are produced in a single cycle. All 8 M-extension instructions are supported with proper RISC-V edge case handling (division by zero, signed overflow).

### CSR Registers & Exception Traps — [`csr_file.v`](csr_file.v)

**The problem without it:** There is no way for the CPU to handle system calls (`ecall`) or hardware exceptions. The processor would just continue executing garbage after encountering one.

**How this module solves it:** Adds 6 machine-mode CSRs. When `ecall` is detected in the ID stage, the control unit asserts `trap_en`. The current PC is saved to `mepc`, the cause code goes to `mcause`, and the pipeline is flushed while the PC redirects to `mtvec` (the trap handler). This is the fundamental mechanism behind operating system calls.

### Synchronous L1 Cache — [`cache_controller.v`](cache_controller.v)

**The problem without it:** Memory access is the slowest part of any real system. A simple processor that goes directly to RAM on every instruction would stall for dozens of cycles per access in a real chip.

**How this module solves it:** Adds a direct-mapped L1 cache with 8 entries and a write-through policy. Frequently accessed data stays in the cache and is returned in 0 stall cycles. On a miss, the controller stalls the pipeline for 4 cycles while fetching from the backing RAM, then the fetched data is installed in the cache for future hits.

---

## 8. System-on-Chip (SoC) Mode

By reserving part of the address space for hardware peripherals, the CPU becomes a System-on-Chip capable of interacting with the outside world. This is implemented entirely in [`top.v`](top.v)'s MEM stage.

```
Memory Map:
  0x00000000  ──────────────────────────────  Instruction ROM
  0x00001FFF  (cached, normal accesses)
  ───────────────────────────────────────────────────────────
  0x00002000  UART Transmit Register (write-only)
  0x00002008  System Timer Register  (read-only, = cycle count)
  (MMIO space — bypasses all caches)
```

Any write to `0x00002000` is intercepted in simulation and the byte is printed as an ASCII character to the terminal. Any read from `0x00002008` returns the current value of the 32-bit cycle counter.

**Test the SoC mode:**
```bash
iverilog -s tb_soc -o sim_soc tb_soc.v && ./sim_soc
```
Expected output:
```
RISC-V SOC OK
PASS: System Timer value read successfully: 210 cycles
```

---

## 9. C++ Co-Simulation Verification

Simply running simulation and checking a few register values is not enough to prove a pipelined processor is correct. A forwarding bug might cause one specific sequence to fail while all your tests pass. To make verification rigorous, this project uses a **Co-Simulation framework**:

**The idea:** Run the same program on two completely independent simulators — one is a simple, obviously correct C++ model; the other is the actual Verilog pipeline. Compare every single architectural state change they produce. If they match 100%, the pipelined implementation is correct.

| File | Role |
|---|---|
| [`riscv_iss.cpp`](riscv_iss.cpp) | The C++ "Golden Reference" — a simple switch-statement interpreter that executes instructions one by one, no pipelining, no caches, just pure ISA semantics. Every register/memory write is logged. |
| [`tb_cosim.v`](tb_cosim.v) | Runs the Verilog pipeline. Watches for retired instruction writebacks at the WB stage. Logs each register/memory write to a trace file, ignoring pipeline stalls and flushed bubbles. |
| [`compare.py`](compare.py) | Orchestrates everything: compiles both simulators, runs them, then diffs the two trace files line-by-line. |

**Run it:**
```bash
python3 compare.py
```

**Inject a Bug to Test the Framework:**
1. Open [`alu.v`](alu.v) and change one line:
   ```diff
   - 4'b0010: result = a + b; // ADD
   + 4'b0010: result = a - b; // BUG
   ```
2. Run `python3 compare.py` — you will instantly see:
   ```
   ❌ Mismatch at event 1:
      Golden ISS : x1 = 0000000a
      Verilog CPU: x1 = fffffff6
   ```
3. Restore [`alu.v`](alu.v) and re-run to confirm:
   ```
   🎉 CO-SIMULATION SUCCESS: traces match 100%!
   Successfully verified 34 architectural events.
   ```

---

## 10. Bug Fixes Applied to This Codebase

During development, several correctness issues were identified and patched. These are documented here for transparency and learning value.

### 🔴 Critical Correctness Fixes

**1. Missing `else` in CSR File — [`csr_file.v`](csr_file.v)**
The sequential always block had `end begin` instead of `end else begin`, meaning the counter increment block ran on *every* clock edge including the reset cycle. Since Verilog non-blocking assignments resolve simultaneously, the later assignment (increment) overwrote the reset assignment — so `mcycle` never actually reset to zero.
```diff
- end begin
+ end else begin
    mcycle <= mcycle + 32'd1;
```

**2. Wrong Priority in PC Mux — [`top.v`](top.v)**
The `pc_next` mux checked `id_mispredict` before `stall_pc`. This meant during a cache miss (where the whole pipeline should freeze), the PC would still jump to a speculative branch target computed from stale operand values. Fixed by checking `stall_pc` first.
```diff
  assign pc_next = id_trap_en   ? mtvec_out :
- id_mispredict ? id_mispredict_target :
  stall_pc      ? pc_current :
+ id_mispredict ? id_mispredict_target :
```

**3. LUI and AUIPC Never Decoded — [`control.v`](control.v)**
`imm_gen.v` and `hazard_unit.v` both had support for `LUI`/`AUIPC`, but `control.v` had no case for their opcodes, so they fell through to `default` (all signals zero) and wrote nothing. Fixed by adding both opcodes to the decode case block and adding an operand-A mux in the EX stage of `top.v` to feed `0` (for LUI) or `pc` (for AUIPC) to the ALU.

### 🟡 Masked Correctness Issues

**4. MEM Forwarding Used Address Instead of Load Data — [`top.v`](top.v)**
The ID-stage branch comparison forwarding and EX-stage ALU forwarding both unconditionally selected `mem_alu_result` when a MEM-stage instruction had a matching `rd`. But for a `lw` in MEM, `mem_alu_result` is the *address* being loaded, not the loaded data. The fix introduces `mem_forward_data` which selects `final_mem_read_data` (the actual loaded word) when `mem_MemToReg` is asserted.

**5. CSR-Immediate Instructions Caused False Hazard Stalls — [`hazard_unit.v`](hazard_unit.v)**
Instructions like `csrrwi` use the `rs1` field as a 5-bit literal immediate, not a register index. The hazard unit was treating it as a register read, potentially inserting unnecessary stall cycles if the literal value numerically collided with a nearby destination register. Fixed by detecting CSR-immediate instructions via `funct3[2]` and excluding them from `id_reads_rs1`.

### 🟢 Hygiene and Cleanup

**6. BTB Left Stale on Not-Taken Update — [`branch_predictor.v`](branch_predictor.v)**
When a branch resolved as not-taken, the BHT bit was cleared but `btb_valid` was left high with stale target data. Fixed by also clearing `btb_valid` on not-taken updates.

**7. Wrong Memory Comment — [`data_mem.v`](data_mem.v)**
The file header said "asynchronous read" but the read logic was inside `always @(posedge clk)` — a synchronous read. Fixed the comment.

**8. Dead Code Removed — [`top.v`](top.v)**
`assign take_branch = 1'b0;` was a vestige of an earlier design where branches resolved in the MEM stage. Removed.
