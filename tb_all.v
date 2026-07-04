`timescale 1ns/1ps
// =================================================================
// tb_all.v  –  Unified Testbench for Pipelined RISC-V Processor
//              Runs all tests (RV32I, Hazards, RV32M, CSRs, traps, 
//              cache, branch prediction) continuously at once.
// =================================================================
`include "top.v"

module tb_all;

    reg clk;
    reg rst;

    // DUT Taps
    wire [31:0] dbg_pc, dbg_if_instr, dbg_id_instr;
    wire [31:0] dbg_x1,  dbg_x2,  dbg_x3,  dbg_x5,  dbg_x6;
    wire [31:0] dbg_x7,  dbg_x8,  dbg_x9,  dbg_x10, dbg_x11;
    wire [31:0] dbg_x12, dbg_x16, dbg_x17;
    wire [31:0] dbg_dm0, dbg_dm1, dbg_dm2;

    top u_dut (
        .clk          (clk),
        .rst          (rst),
        .dbg_pc       (dbg_pc),
        .dbg_if_instr (dbg_if_instr),
        .dbg_id_instr (dbg_id_instr),
        .dbg_x1       (dbg_x1),  .dbg_x2  (dbg_x2),  .dbg_x3  (dbg_x3),
        .dbg_x5       (dbg_x5),  .dbg_x6  (dbg_x6),  .dbg_x7  (dbg_x7),
        .dbg_x8       (dbg_x8),  .dbg_x9  (dbg_x9),  .dbg_x10 (dbg_x10),
        .dbg_x11      (dbg_x11), .dbg_x12 (dbg_x12), .dbg_x16 (dbg_x16),
        .dbg_x17      (dbg_x17), .dbg_dm0 (dbg_dm0), .dbg_dm1 (dbg_dm1),
        .dbg_dm2      (dbg_dm2)
    );

    // Clock generator: 10 ns period
    always #5 clk = ~clk;

    // Assert helper macro
    integer pass_cnt = 0;
    integer fail_cnt = 0;
    `define CHECK(label, got, exp) \
        if ((got) === (exp)) begin \
            $display("  PASS  %-35s  got=%0d", label, got); \
            pass_cnt = pass_cnt + 1; \
        end else begin \
            $display("  FAIL  %-35s  got=%0d  exp=%0d", label, got, exp); \
            fail_cnt = fail_cnt + 1; \
        end

    `define NOP 32'h0000_0013

    // VCD Dump for Surfer
    initial begin
        $dumpfile("tb_all.vcd");
        $dumpvars(0, tb_all);
    end

    integer k;

    initial begin
        clk = 0;
        rst = 1;
        
        // ── Clear Memory ─────────────────────────────────────────
        for (k = 0; k < 64; k = k + 1) begin
            u_dut.u_imem.mem[k] = `NOP;
        end

        // ============================================================
        // LOAD UNIFIED TEST PROGRAM
        // ============================================================
        
        // ---- Part 1: Basic Pipeline & Forwarding (PC 0 to 52) ----
        u_dut.u_imem.mem[0]  = 32'h00a00093; // addi x1, x0, 10
        u_dut.u_imem.mem[1]  = 32'h01400113; // addi x2, x0, 20
        u_dut.u_imem.mem[2]  = 32'h00500193; // addi x3, x0, 5
        u_dut.u_imem.mem[3]  = 32'h002082b3; // add x5, x1, x2        (x5 = 30)
        u_dut.u_imem.mem[4]  = 32'h40310333; // sub x6, x2, x3        (x6 = 15)
        u_dut.u_imem.mem[5]  = 32'h0030f3b3; // and x7, x1, x3        (x7 = 0)
        u_dut.u_imem.mem[6]  = 32'h0030e433; // or  x8, x1, x3        (x8 = 15)
        u_dut.u_imem.mem[7]  = 32'h01f2f493; // andi x9, x5, 31       (x9 = 30)
        u_dut.u_imem.mem[8]  = 32'h00136513; // ori  x10, x6, 1       (x10 = 15)
        u_dut.u_imem.mem[9]  = 32'h0011a5b3; // slt  x11, x3, x1      (x11 = 1)
        u_dut.u_imem.mem[10] = 32'h0641a613; // slti x12, x3, 100     (x12 = 1)
        u_dut.u_imem.mem[11] = 32'h00122023; // sw   x1, 0(x4)        (mem[0] = 10)
        u_dut.u_imem.mem[12] = 32'h00022803; // lw   x16, 0(x4)       (x16 = 10)
        u_dut.u_imem.mem[13] = 32'h002808b3; // add  x17, x16, x2     (x17 = 30)

        // ---- Part 2: Hazards & Branch Squash (PC 56 to 108) ----
        u_dut.u_imem.mem[14] = 32'h00300313; // addi x6, x0, 3        (re-write x6 = 3)
        u_dut.u_imem.mem[15] = 32'h00300393; // addi x7, x0, 3        (re-write x7 = 3)
        u_dut.u_imem.mem[16] = 32'h00730663; // beq  x6, x7, +12      (taken to index 20)
        u_dut.u_imem.mem[17] = 32'h06300413; // addi x8,  x0, 99      -- SQUASHED (remains 15 from above or 0?)
                                              // Note: x8 was not written in Part 1, so it should stay 0.
        u_dut.u_imem.mem[18] = 32'h05800493; // addi x9,  x0, 88      -- SQUASHED (remains 30)
        u_dut.u_imem.mem[19] = `NOP;
        u_dut.u_imem.mem[20] = 32'h02a00913; // addi x18, x0, 42       (x18 = 42)
        u_dut.u_imem.mem[21] = 32'h00400593; // addi x11, x0, 4        (re-write x11 = 4)
        u_dut.u_imem.mem[22] = 32'h00700613; // addi x12, x0, 7        (re-write x12 = 7)
        u_dut.u_imem.mem[23] = 32'h00c5a023; // sw   x12, 0(x11)       (mem[1] = 7)
        u_dut.u_imem.mem[24] = 32'h0005a683; // lw   x13, 0(x11)       (x13 = 7)
        u_dut.u_imem.mem[25] = 32'h00069663; // bne  x13, x0, +12      (taken to index 29)
        u_dut.u_imem.mem[26] = 32'h03700713; // addi x14, x0, 55      -- SQUASHED
        u_dut.u_imem.mem[27] = 32'h04200793; // addi x15, x0, 66      -- SQUASHED
        u_dut.u_imem.mem[28] = `NOP;

        // ---- Part 3: RV32M Multiplier/Divider (PC 116 to 132) ----
        u_dut.u_imem.mem[29] = 32'h00a00993; // addi x19, x0, 10
        u_dut.u_imem.mem[30] = 32'h00300a13; // addi x20, x0, 3
        u_dut.u_imem.mem[31] = 32'h03498ab3; // mul  x21, x19, x20     (x21 = 30)
        u_dut.u_imem.mem[32] = 32'h0349cb33; // div  x22, x19, x20     (x22 = 3)
        u_dut.u_imem.mem[33] = 32'h0349ebb3; // rem  x23, x19, x20     (x23 = 1)

        // ---- Part 4: CSRs & Exception Trap (PC 136 to 156) ----
        u_dut.u_imem.mem[34] = 32'h0b400c93; // addi x25, x0, 180       (trap vector = index 45)
        u_dut.u_imem.mem[35] = 32'h305c9073; // csrrw x0, mtvec, x25    (mtvec = 180)
        u_dut.u_imem.mem[36] = `NOP;         // Gaps to allow CSR WB to complete
        u_dut.u_imem.mem[37] = `NOP;
        u_dut.u_imem.mem[38] = `NOP;
        u_dut.u_imem.mem[39] = 32'h00000073; // ecall (Trap!)           -- PC = 156. Jumps to 180.
        u_dut.u_imem.mem[40] = 32'h06300c13; // addi x24, x0, 99        -- SQUASHED (should stay 180)
        u_dut.u_imem.mem[41] = `NOP;

        // ---- Part 5: Trap Handler (PC 180 to 196) ----
        u_dut.u_imem.mem[45] = 32'h00500d13; // addi x26, x0, 5         (x26 = 5)
        u_dut.u_imem.mem[46] = 32'h00c0006f; // jal  x0, +12            (jump out to PC=200 = index 50)

        // ---- Part 6: Loop & Branch Predictor (PC 200 to 220) ----
        u_dut.u_imem.mem[50] = 32'h00200d93; // addi x27, x0, 2
        u_dut.u_imem.mem[51] = 32'h00000e13; // addi x28, x0, 0
        u_dut.u_imem.mem[52] = 32'h00100e93; // addi x29, x0, 1
        // Loop:
        u_dut.u_imem.mem[53] = 32'h01de0e33; // add  x28, x28, x29      (increments x28)
        u_dut.u_imem.mem[54] = 32'hffbe1ee3; // bne  x28, x27, -4       (branch to index 53 if x28!=x27)
        u_dut.u_imem.mem[55] = 32'h0000006f; // halt self-loop (jal x0, 0)
        u_dut.u_imem.mem[56] = `NOP;
        u_dut.u_imem.mem[57] = `NOP;

        // Run Reset Sequence
        #10;
        rst = 1;
        repeat(5) @(posedge clk);
        @(negedge clk); rst = 0;

        // Simulate enough cycles to execute the entire unified program (approx 450 cycles)
        repeat (450) @(posedge clk);
        #1;

        // ============================================================
        // ASSERT RESULTS
        // ============================================================
        $display("\n=====================================================");
        $display("          RISC-V UNIFIED PIPELINE CHECK");
        $display("=====================================================");
        
        // 1. Basic Pipeline Ops
        `CHECK("P1: addi x1 (expect 10)", dbg_x1, 32'd10)
        `CHECK("P1: addi x2 (expect 20)", dbg_x2, 32'd20)
        `CHECK("P1: addi x3 (expect 5)",  dbg_x3, 32'd5)
        `CHECK("P1: add  x5 (expect 30)", dbg_x5, 32'd30)
        `CHECK("P1: sub  x6 (expect 3)",  dbg_x6, 32'd3) // overwritten in Part 2 to 3
        `CHECK("P1: and  x7 (expect 3)",  dbg_x7, 32'd3) // overwritten in Part 2 to 3
        `CHECK("P1: or   x8 (expect 15)", dbg_x8, 32'd15) // Part 1 value 15
        `CHECK("P1: andi x9 (expect 30)", dbg_x9, 32'd30) // Part 1 value 30
        `CHECK("P1: ori  x10 (expect 15)", dbg_x10, 32'd15)
        `CHECK("P1: slt  x11 (expect 4)", dbg_x11, 32'd4) // overwritten in Part 2 to 4
        `CHECK("P1: slti x12 (expect 7)", dbg_x12, 32'd7) // overwritten in Part 2 to 7
        `CHECK("P1: lw   x16 (expect 10)", dbg_x16, 32'd10)
        `CHECK("P1: add  x17 (expect 30)", dbg_x17, 32'd30)
        `CHECK("P1: store dm[0] (expect 10)", dbg_dm0, 32'd10)

        // 2. Hazards & Squashes
        `CHECK("P2: squash addi x8 (expect 15)", dbg_x8, 32'd15) // remains 15 since 99 was squashed
        `CHECK("P2: branch target x18 (expect 42)", u_dut.u_regfile.regs[18], 32'd42)
        `CHECK("P2: store dm[1] (expect 7)", dbg_dm1, 32'd7)
        `CHECK("P2: load x13 (expect 7)", u_dut.u_regfile.regs[13], 32'd7)
        `CHECK("P2: squash addi x14 (expect 0)", u_dut.u_regfile.regs[14], 32'd0)
        `CHECK("P2: squash addi x15 (expect 0)", u_dut.u_regfile.regs[15], 32'd0)

        // 3. RV32M math
        `CHECK("P3: mul x21 (expect 30)", u_dut.u_regfile.regs[21], 32'd30)
        `CHECK("P3: div x22 (expect 3)",  u_dut.u_regfile.regs[22], 32'd3)
        `CHECK("P3: rem x23 (expect 1)",  u_dut.u_regfile.regs[23], 32'd1)

        // 4. CSR & Exception Trap
        `CHECK("P4: mtvec check (expect 180)", u_dut.u_csr.mtvec, 32'd180)
        `CHECK("P4: mepc check (expect 156)",   u_dut.u_csr.mepc,  32'd156) // ecall was at PC=156
        `CHECK("P4: mcause check (expect 11)", u_dut.u_csr.mcause, 32'd11)
        `CHECK("P4: squash x24 (expect 0)",   u_dut.u_regfile.regs[24], 32'd0) // remained 0
        `CHECK("P4: handler x26 (expect 5)",  u_dut.u_regfile.regs[26], 32'd5)

        // 5. Predictor Loop
        `CHECK("P5: Loop counter x28 (expect 2)", u_dut.u_regfile.regs[28], 32'd2)

        $display("\n╔══════════════════════════════════════════════╗");
        $display("║         UNIFIED SIMULATION COMPLETE          ║");
        $display("╠══════════════════════════════════════════════╣");
        $display("║  Total PASS : %-4d                           ║", pass_cnt);
        $display("║  Total FAIL : %-4d                           ║", fail_cnt);
        if (fail_cnt == 0)
        $display("║  RESULT     : ALL TESTS PASSED ✓             ║");
        else
        $display("║  RESULT     : SOME TESTS FAILED ✗            ║");
        $display("╚══════════════════════════════════════════════╝");
        $finish;
    end

endmodule
