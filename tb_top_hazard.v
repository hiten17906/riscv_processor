// ============================================================
// tb_top_hazard.v  –  Testbench for Part 2 Pipelined RISC-V
//                     (Hazard Detection + Forwarding Unit)
//
// Branch is resolved in the MEM stage in this implementation,
// so a taken branch flushes 2 instructions (IF + ID stages).
//
// Three test sequences loaded into instruction memory:
//
// ── (a) DATA HAZARDS only  [addr 0..7] ───────────────────
//   Back-to-back dependent instructions — forwarding unit
//   handles write-use; hazard unit inserts 1 bubble for lw.
//
//   [0]  addi x1, x0, 5      # x1 = 5
//   [1]  add  x2, x1, x1     # x2 = 10  (EX/MEM→EX fwd A+B)
//   [2]  add  x3, x2, x1     # x3 = 15  (EX/MEM→A, MEM/WB→B)
//   [3]  sw   x3, 0(x0)      # mem[0] = 15
//   [4]  lw   x4, 0(x0)      # x4 = 15
//   [5]  add  x5, x4, x3     # x5 = 30  (load-use stall on x4)
//   [6]  nop
//   [7]  nop
//   Expected: x1=5 x2=10 x3=15 x4=15 x5=30  dm[0]=15
//
// ── (b) CONTROL HAZARD only  [addr 8..19] ────────────────
//   A taken beq flushes 2 instructions after it (MEM-stage
//   branch resolution → 2-cycle penalty).
//
//   [8]  addi x6,  x0, 3     # x6 = 3
//   [9]  addi x7,  x0, 3     # x7 = 3
//   [10] nop                  # spacer so x6/x7 reach WB
//   [11] nop
//   [12] nop
//   [13] beq  x6, x7, +12    # taken → target = 0x34+12 = 0x40 → [16]
//   [14] addi x8,  x0, 99    # SQUASHED (flush 1)
//   [15] addi x9,  x0, 88    # SQUASHED (flush 2)
//   [16] addi x10, x0, 42    # x10 = 42  (branch target)
//   [17..19] nop
//   Expected: x6=3 x7=3 x8=0 x9=0 x10=42
//
// ── (c) DATA + CONTROL HAZARD  [addr 20..37] ─────────────
//   lw followed (with gap) by bne that uses loaded value;
//   load-use stall (1 cycle) + branch flush (2 cycles).
//
//   [20] addi x11, x0, 4     # x11 = 4  (base address = byte 4)
//   [21] addi x12, x0, 7     # x12 = 7
//   [22] sw   x12, 0(x11)    # mem[1] = 7
//   [23] nop
//   [24] nop
//   [25] lw   x13, 0(x11)    # x13 = 7
//   [26] nop                  # ensure lw reaches WB before branch reads x13
//   [27] nop
//   [28] nop
//   [29] bne  x13, x0, +12   # x13!=0 → taken → target=0x74+12=0x80→[32]
//   [30] addi x14, x0, 55    # SQUASHED
//   [31] addi x15, x0, 66    # SQUASHED
//   [32] addi x16, x0, 99    # x16 = 99
//   [33..37] nop (drain)
//   Expected: x13=7 x14=0 x15=0 x16=99  dm[1]=7
// ============================================================

`timescale 1ns/1ps
`include "top.v"

module tb_top_hazard;

    // ── DUT ports ─────────────────────────────────────────
    reg  clk, rst;

    wire [31:0] dbg_pc, dbg_if_instr, dbg_id_instr;
    wire [31:0] dbg_x1,  dbg_x2,  dbg_x3,  dbg_x5;
    wire [31:0] dbg_x6,  dbg_x7,  dbg_x8,  dbg_x9;
    wire [31:0] dbg_x10, dbg_x11, dbg_x12, dbg_x16, dbg_x17;
    wire [31:0] dbg_dm0, dbg_dm1, dbg_dm2;

    top u_dut (
        .clk          (clk),
        .rst          (rst),
        .dbg_pc       (dbg_pc),
        .dbg_if_instr (dbg_if_instr),
        .dbg_id_instr (dbg_id_instr),
        .dbg_x1       (dbg_x1),
        .dbg_x2       (dbg_x2),
        .dbg_x3       (dbg_x3),
        .dbg_x5       (dbg_x5),
        .dbg_x6       (dbg_x6),
        .dbg_x7       (dbg_x7),
        .dbg_x8       (dbg_x8),
        .dbg_x9       (dbg_x9),
        .dbg_x10      (dbg_x10),
        .dbg_x11      (dbg_x11),
        .dbg_x12      (dbg_x12),
        .dbg_x16      (dbg_x16),
        .dbg_x17      (dbg_x17),
        .dbg_dm0      (dbg_dm0),
        .dbg_dm1      (dbg_dm1),
        .dbg_dm2      (dbg_dm2)
    );

    // ── Clock: 10 ns period ───────────────────────────────
    initial clk = 0;
    always  #5 clk = ~clk;

    // ── VCD dump (open GTKWave with tb_top_hazard.vcd) ────
    initial begin
        $dumpfile("tb_top_hazard.vcd");
        $dumpvars(0, tb_top_hazard);
    end

    // ── Load instruction memory ───────────────────────────
    initial begin

        // ── (a) DATA HAZARD  [0..7] ───────────────────────
        u_dut.u_imem.mem[0]  = 32'h00500093; // addi x1, x0, 5
        u_dut.u_imem.mem[1]  = 32'h00108133; // add  x2, x1, x1
        u_dut.u_imem.mem[2]  = 32'h001101B3; // add  x3, x2, x1
        u_dut.u_imem.mem[3]  = 32'h00302023; // sw   x3, 0(x0)
        u_dut.u_imem.mem[4]  = 32'h00002203; // lw   x4, 0(x0)
        u_dut.u_imem.mem[5]  = 32'h003202B3; // add  x5, x4, x3
        u_dut.u_imem.mem[6]  = 32'h00000013; // nop
        u_dut.u_imem.mem[7]  = 32'h00000013; // nop

        // ── (b) CONTROL HAZARD  [8..19] ───────────────────
        u_dut.u_imem.mem[8]  = 32'h00300313; // addi x6, x0, 3
        u_dut.u_imem.mem[9]  = 32'h00300393; // addi x7, x0, 3
        u_dut.u_imem.mem[10] = 32'h00000013; // nop
        u_dut.u_imem.mem[11] = 32'h00000013; // nop
        u_dut.u_imem.mem[12] = 32'h00000013; // nop
        // beq x6, x7, +12  (PC=0x34, target=0x34+12=0x40=[16])
        // B-type: imm=12, rs1=x6(00110), rs2=x7(00111), funct3=000
        // encoding: 0_000000_00111_00110_000_0110_0_1100011 = 00730663
        u_dut.u_imem.mem[13] = 32'h00730663; // beq x6, x7, +12
        u_dut.u_imem.mem[14] = 32'h06300413; // addi x8,  x0, 99  -- SQUASHED
        u_dut.u_imem.mem[15] = 32'h05800493; // addi x9,  x0, 88  -- SQUASHED
        u_dut.u_imem.mem[16] = 32'h02A00513; // addi x10, x0, 42  (target)
        u_dut.u_imem.mem[17] = 32'h00000013; // nop
        u_dut.u_imem.mem[18] = 32'h00000013; // nop
        u_dut.u_imem.mem[19] = 32'h00000013; // nop

        // ── (c) DATA + CONTROL HAZARD  [20..37] ───────────
        u_dut.u_imem.mem[20] = 32'h00400593; // addi x11, x0, 4
        u_dut.u_imem.mem[21] = 32'h00700613; // addi x12, x0, 7
        // sw x12, 0(x11): S-type rs1=x11(01011) rs2=x12(01100) imm=0
        // 0000000_01100_01011_010_00000_0100011 = 00C5A023
        u_dut.u_imem.mem[22] = 32'h00C5A023; // sw   x12, 0(x11)
        u_dut.u_imem.mem[23] = 32'h00000013; // nop
        u_dut.u_imem.mem[24] = 32'h00000013; // nop
        // lw x13, 0(x11): I-type rs1=x11(01011) rd=x13(01101) imm=0
        // 000000000000_01011_010_01101_0000011 = 0005A683
        u_dut.u_imem.mem[25] = 32'h0005A683; // lw   x13, 0(x11)
        u_dut.u_imem.mem[26] = 32'h00000013; // nop  (let lw reach WB)
        u_dut.u_imem.mem[27] = 32'h00000013; // nop
        u_dut.u_imem.mem[28] = 32'h00000013; // nop
        // bne x13, x0, +12  (PC=0x74=116, target=116+12=128=0x80=[32])
        // B-type: imm=12, rs1=x13(01101), rs2=x0(00000), funct3=001
        // 0_000000_00000_01101_001_0110_0_1100011 = 00069663
        u_dut.u_imem.mem[29] = 32'h00069663; // bne  x13, x0, +12
        u_dut.u_imem.mem[30] = 32'h03700713; // addi x14, x0, 55  -- SQUASHED
        u_dut.u_imem.mem[31] = 32'h04200793; // addi x15, x0, 66  -- SQUASHED
        u_dut.u_imem.mem[32] = 32'h06300813; // addi x16, x0, 99  (target)
        u_dut.u_imem.mem[33] = 32'h00000013; // nop (drain)
        u_dut.u_imem.mem[34] = 32'h00000013;
        u_dut.u_imem.mem[35] = 32'h00000013;
        u_dut.u_imem.mem[36] = 32'h00000013;
        u_dut.u_imem.mem[37] = 32'h00000013;
    end

    // ── Reset then run ────────────────────────────────────
    initial begin
        rst = 1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst = 0;

        // 38 instructions + hazard bubbles + cache misses + drain ≈ 400 cycles
        repeat (400) @(posedge clk);

        // ── Display results ────────────────────────────────
        $display("\n========== (a) DATA HAZARD ==========");
        $display("x1  (expect  5) = %0d", u_dut.u_regfile.regs[1]);
        $display("x2  (expect 10) = %0d", u_dut.u_regfile.regs[2]);
        $display("x3  (expect 15) = %0d", u_dut.u_regfile.regs[3]);
        $display("x4  (expect 15) = %0d", u_dut.u_regfile.regs[4]);
        $display("x5  (expect 30) = %0d", u_dut.u_regfile.regs[5]);
        $display("dm[0] (expect 15) = %0d", u_dut.u_dmem.mem[0]);

        $display("\n========== (b) CONTROL HAZARD ==========");
        $display("x6  (expect  3)          = %0d", u_dut.u_regfile.regs[6]);
        $display("x7  (expect  3)          = %0d", u_dut.u_regfile.regs[7]);
        $display("x8  (expect  0, squashed)= %0d", u_dut.u_regfile.regs[8]);
        $display("x9  (expect  0, squashed)= %0d", u_dut.u_regfile.regs[9]);
        $display("x10 (expect 42)          = %0d", u_dut.u_regfile.regs[10]);

        $display("\n========== (c) DATA + CONTROL HAZARD ==========");
        $display("x11 (expect  4)          = %0d", u_dut.u_regfile.regs[11]);
        $display("x12 (expect  7)          = %0d", u_dut.u_regfile.regs[12]);
        $display("x13 (expect  7)          = %0d", u_dut.u_regfile.regs[13]);
        $display("x14 (expect  0, squashed)= %0d", u_dut.u_regfile.regs[14]);
        $display("x15 (expect  0, squashed)= %0d", u_dut.u_regfile.regs[15]);
        $display("x16 (expect 99)          = %0d", u_dut.u_regfile.regs[16]);
        $display("dm[1] (expect  7)        = %0d", u_dut.u_dmem.mem[1]);

        // ── Automated pass/fail ────────────────────────────
        $display("\n========== PASS / FAIL ==========");
        // (a)
        if (u_dut.u_regfile.regs[1]  === 32'd5)  $display("x1   PASS"); else $display("x1   FAIL (got %0d)", u_dut.u_regfile.regs[1]);
        if (u_dut.u_regfile.regs[2]  === 32'd10) $display("x2   PASS"); else $display("x2   FAIL (got %0d)", u_dut.u_regfile.regs[2]);
        if (u_dut.u_regfile.regs[3]  === 32'd15) $display("x3   PASS"); else $display("x3   FAIL (got %0d)", u_dut.u_regfile.regs[3]);
        if (u_dut.u_regfile.regs[4]  === 32'd15) $display("x4   PASS"); else $display("x4   FAIL (got %0d)", u_dut.u_regfile.regs[4]);
        if (u_dut.u_regfile.regs[5]  === 32'd30) $display("x5   PASS"); else $display("x5   FAIL (got %0d)", u_dut.u_regfile.regs[5]);
        if (u_dut.u_dmem.mem[0]      === 32'd15) $display("dm[0] PASS"); else $display("dm[0] FAIL (got %0d)", u_dut.u_dmem.mem[0]);
        // (b)
        if (u_dut.u_regfile.regs[6]  === 32'd3)  $display("x6   PASS"); else $display("x6   FAIL (got %0d)", u_dut.u_regfile.regs[6]);
        if (u_dut.u_regfile.regs[7]  === 32'd3)  $display("x7   PASS"); else $display("x7   FAIL (got %0d)", u_dut.u_regfile.regs[7]);
        if (u_dut.u_regfile.regs[8]  === 32'd0)  $display("x8   PASS (squashed)"); else $display("x8   FAIL – must be 0 (got %0d)", u_dut.u_regfile.regs[8]);
        if (u_dut.u_regfile.regs[9]  === 32'd0)  $display("x9   PASS (squashed)"); else $display("x9   FAIL – must be 0 (got %0d)", u_dut.u_regfile.regs[9]);
        if (u_dut.u_regfile.regs[10] === 32'd42) $display("x10  PASS"); else $display("x10  FAIL (got %0d)", u_dut.u_regfile.regs[10]);
        // (c)
        if (u_dut.u_regfile.regs[11] === 32'd4)  $display("x11  PASS"); else $display("x11  FAIL (got %0d)", u_dut.u_regfile.regs[11]);
        if (u_dut.u_regfile.regs[12] === 32'd7)  $display("x12  PASS"); else $display("x12  FAIL (got %0d)", u_dut.u_regfile.regs[12]);
        if (u_dut.u_regfile.regs[13] === 32'd7)  $display("x13  PASS"); else $display("x13  FAIL (got %0d)", u_dut.u_regfile.regs[13]);
        if (u_dut.u_regfile.regs[14] === 32'd0)  $display("x14  PASS (squashed)"); else $display("x14  FAIL – must be 0 (got %0d)", u_dut.u_regfile.regs[14]);
        if (u_dut.u_regfile.regs[15] === 32'd0)  $display("x15  PASS (squashed)"); else $display("x15  FAIL – must be 0 (got %0d)", u_dut.u_regfile.regs[15]);
        if (u_dut.u_regfile.regs[16] === 32'd99) $display("x16  PASS"); else $display("x16  FAIL (got %0d)", u_dut.u_regfile.regs[16]);
        if (u_dut.u_dmem.mem[1]      === 32'd7)  $display("dm[1] PASS"); else $display("dm[1] FAIL (got %0d)", u_dut.u_dmem.mem[1]);

        $finish;
    end

    // ── Per-cycle pipeline monitor ─────────────────────────
    always @(posedge clk) begin
        if (!rst)
            $display("t=%0t | PC=%h | IF=%h | ID=%h | stall_pc=%b stall_if=%b flush_if=%b flush_id=%b | FwdA=%b FwdB=%b",
                $time,
                dbg_pc,
                dbg_if_instr,
                dbg_id_instr,
                u_dut.stall_pc,
                u_dut.stall_if_id,
                u_dut.flush_if_id,
                u_dut.flush_id_ex,
                u_dut.ForwardA,
                u_dut.ForwardB);
    end

endmodule
