# RISC-V 5-Stage Pipelined Processor SoC (Upgraded & Verified)

Welcome! This repository implements a highly optimized, 5-stage pipelined RISC-V processor in Verilog. It is fully compliant with the RV32I base integer instruction set and includes several advanced upgrades: dynamic branch prediction, the RV32M multiplier/divider extension, CSR (Control and Status Register) exception trap handling, and a synchronous L1 cache memory subsystem.

To showcase these features, the design can run in a **System-on-Chip (SoC) Mode** with Memory-Mapped I/O (MMIO) to print text to a UART console and read a system timer. It is validated using a **C++ Co-Simulation verification suite** that checks the Verilog CPU cycle-by-cycle against a C++ behavioral model.

---

## ⚡ Quick Start: Verify Everything in 5 Seconds

If you want to run the entire verification suite (stalls, hazards, branch predictors, caches, SoC mode, and C++ ISS co-simulation) automatically:

```bash
./verify.sh
```

This shell script compiles, executes, and validates all **6 simulation phases** sequentially.

---

## 🌊 How to View Waveforms in Surfer

Surfer is a high-performance, web-based waveform viewer. You can inspect all internal pipeline registers, hazard stalls, and cache transactions:

1.  **Generate the Waveform Database:**
    Run the unified comprehensive testbench:
    ```bash
    iverilog -s tb_all -o sim_all tb_all.v && ./sim_all
    ```
    This outputs `tb_all.vcd` in your folder.
2.  **Open Surfer:**
    Go to **[surfer.app](https://surfer.app/)** in your browser.
3.  **Inspect Signals:**
    Drag and drop the generated `tb_all.vcd` file into the page. Expand the tree in the left panel (`tb_all` ➔ `u_dut`) to drag signals (like `clk`, `pc_current`, `regs`, `dcache_stall`, and pipeline register states) onto the timeline!

---

## 🏗️ Hardware Architecture & File Map

The processor splits instruction execution into a classic 5-stage pipeline. Click any file link below to view its source implementation:

```text
       [IF] ➔➔➔➔➔➔➔➔➔ [ID] ➔➔➔➔➔➔➔➔➔ [EX] ➔➔➔➔➔➔➔➔➔ [MEM] ➔➔➔➔➔➔➔➔➔ [WB]
   Fetch Instr     Decode & Reg     Execute ALU      Read/Write      Write Back
   (Cache / BTB)    (Forwarding)    (RV32M / CSR)    (Cache / MMIO)   (To Regfile)
```

| Component | Source File | Description |
|---|---|---|
| **Top Core** | [top.v](file:///Users/hitens/Desktop/core/COA/assignment5/top.v) | Top-level module connecting all pipeline registers, stages, and wiring. |
| **Fetch (IF)** | [pc.v](file:///Users/hitens/Desktop/core/COA/assignment5/pc.v) <br> [instr_mem.v](file:///Users/hitens/Desktop/core/COA/assignment5/instr_mem.v) | Program counter register and synchronous instruction memory (ROM). |
| **Decode (ID)** | [reg_file.v](file:///Users/hitens/Desktop/core/COA/assignment5/reg_file.v) <br> [imm_gen.v](file:///Users/hitens/Desktop/core/COA/assignment5/imm_gen.v) <br> [control.v](file:///Users/hitens/Desktop/core/COA/assignment5/control.v) | Asynchronous read, write-first register file, immediate generator, and decode control unit. |
| **Execute (EX)** | [alu_control.v](file:///Users/hitens/Desktop/core/COA/assignment5/alu_control.v) <br> [alu.v](file:///Users/hitens/Desktop/core/COA/assignment5/alu.v) <br> [mult_div.v](file:///Users/hitens/Desktop/core/COA/assignment5/mult_div.v) | ALU control logic, basic arithmetic unit, and RV32M multiply/divide block. |
| **Memory (MEM)** | [data_mem.v](file:///Users/hitens/Desktop/core/COA/assignment5/data_mem.v) <br> [cache_controller.v](file:///Users/hitens/Desktop/core/COA/assignment5/cache_controller.v) | Synchronous data RAM and the L1 Data Cache hit/miss controller. |
| **Hazards** | [hazard_unit.v](file:///Users/hitens/Desktop/core/COA/assignment5/hazard_unit.v) <br> [forwarding_unit.v](file:///Users/hitens/Desktop/core/COA/assignment5/forwarding_unit.v) | Pipeline stall controller and operand forwarding bypass unit. |
| **Registers** | `if_id_reg.v`, `id_ex_reg.v`, `ex_mem_reg.v`, `mem_wb_reg.v` | Pipeline registers separating each execution stage. |
| **CSRs** | [csr_file.v](file:///Users/hitens/Desktop/core/COA/assignment5/csr_file.v) | Control & Status Register file managing exception trap vectors. |

---

## ⚡ Advanced Hardware Upgrades Explained

### 1. Dynamic Branch Prediction (0-Cycle Penalty)
*   **Module:** [branch_predictor.v](file:///Users/hitens/Desktop/core/COA/assignment5/branch_predictor.v)
*   **How it works:** Real processors can't wait for branches to resolve. This module instantiates a 1-bit Branch History Table (BHT) to track if a branch is taken, and a Branch Target Buffer (BTB) to cache the target address. In the **IF stage**, the PC checks the BTB. If it hits and is predicted taken, the PC redirects immediately, yielding a **0-cycle branch penalty**. If the prediction is wrong, it is corrected in the **ID stage** (1-cycle flush penalty).

### 2. RV32M Extension (Multiplier & Divider)
*   **Module:** [mult_div.v](file:///Users/hitens/Desktop/core/COA/assignment5/mult_div.v)
*   **How it works:** Adds hardware support for signed/unsigned multiplication (`mul`, `mulh`, `mulhu`, `mulhsu`) and division/remainder (`div`, `divu`, `rem`, `remu`) in the Execute (EX) stage. Handles standard RISC-V edge cases (like division by zero returning `-1` and signed overflows returning the dividend).

### 3. CSR Registers and Trap Handling
*   **Module:** [csr_file.v](file:///Users/hitens/Desktop/core/COA/assignment5/csr_file.v)
*   **How it works:** Manages system status and counter registers (`mstatus`, `mtvec`, `mepc`, `mcause`, `mcycle`, `minstret`). If an `ecall` or `ebreak` is decoded, the CPU flushes the pipeline, saves the offending PC to `mepc`, writes the cause to `mcause`, and jumps immediately to the trap handler address in `mtvec`.

### 4. Synchronous Cache Memory Subsystem
*   **Module:** [cache_controller.v](file:///Users/hitens/Desktop/core/COA/assignment5/cache_controller.v)
*   **How it works:** Replaces asynchronous memory with clocked Block RAM. A direct-mapped L1 cache controller with a write-through policy sits between the CPU and memory. On a cache miss, the controller asserts `cpu_stall` for **4 cycles** to simulate main memory retrieval latency while fetching data.

---

## 🔌 System-on-Chip (SoC) Mode

By mapping hardware peripherals to the memory address space, we can run the CPU in **SoC Mode**. Memory requests are decoded in the MEM stage of [top.v](file:///Users/hitens/Desktop/core/COA/assignment5/top.v):

*   **RAM/ROM Address Space:** Addresses `< 0x00002000` route through the L1 caches.
*   **Uncacheable MMIO Space:** Addresses `>= 0x00002000` bypass the caches to prevent stale reads on hardware:
    *   **UART Print Register (`0x00002000`):** Writing a byte here outputs the ASCII character to your simulation terminal.
    *   **System Timer Register (`0x00002008`):** Reading this address returns the 32-bit clock cycle count.

### Test the SoC Output:
Run the SoC simulation to watch the CPU print characters and report execution cycles:
```bash
iverilog -o sim_soc tb_soc.v && ./sim_soc
```

---

## 🔍 The Co-Simulation Verification Framework

To guarantee correctness, the project uses a cycle-by-cycle **Instruction-Set Simulator (ISS) Co-Simulation** framework:

1.  [riscv_iss.cpp](file:///Users/hitens/Desktop/core/COA/assignment5/riscv_iss.cpp) implements a single-cycle, non-pipelined reference CPU in C++ that is easy to prove correct.
2.  [tb_cosim.v](file:///Users/hitens/Desktop/core/COA/assignment5/tb_cosim.v) runs the pipelined Verilog CPU. As instructions retire at the end of the pipeline, the testbench logs register and memory writes to `cpu_trace.log`, ignoring stalls and speculative flushes.
3.  [compare.py](file:///Users/hitens/Desktop/core/COA/assignment5/compare.py) compiles both models, runs the simulation, and compares the logs line-by-line.

### Run Co-Simulation manually:
```bash
python3 compare.py
```

---

## 🛠️ Step-by-Step Guide: How to Prove it Works (Inject a Bug)

To verify that the co-simulation framework catches logic errors:

1.  Open the ALU source file: [alu.v](file:///Users/hitens/Desktop/core/COA/assignment5/alu.v).
2.  Temporarily break the addition logic (change line 18):
    ```diff
    - 4'b0010: result = a + b; // ADD
    + 4'b0010: result = a - b; // BUG: ADD performs SUB instead
    ```
3.  Execute the co-simulation:
    ```bash
    python3 compare.py
    ```
4.  **Result:** The script will instantly halt and print the exact register mismatch on the first instruction!
    ```text
    ❌ Mismatch at cycle/instruction 1:
       Golden ISS : x1 = 0000000a
       Verilog CPU: x1 = fffffff6
    ```
5.  Restore [alu.v](file:///Users/hitens/Desktop/core/COA/assignment5/alu.v) back to normal and run the check again to see the success banner:
    ```text
    ============================================================
       🎉 CO-SIMULATION SUCCESS: traces match 100%!
    ============================================================
    ```
