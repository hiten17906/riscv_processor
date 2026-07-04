`timescale 1ns/1ps
// ================================================================
// tb_hazard_fwd.v  –  Targeted Testbench for
//                     Forwarding Unit  +  Hazard Detection Unit
//
// Five self-contained TEST GROUPS are loaded sequentially.
// Each group resets the processor, loads a tight instruction
// sequence (NO manual NOPs between dependent instructions) and
// checks the exact register / memory outcome.
//
// TEST GROUP SUMMARY
// ──────────────────
// G1 – MEM→EX  forwarding   : back-to-back ALU instructions
// G2 – WB→EX   forwarding   : instruction two slots behind
// G3 – Load-Use stall        : lw immediately followed by use
// G4 – Double-forwarding     : both rs1 and rs2 forwarded in
//                              the same instruction
// G5 – Branch flush          : beq taken, squash two fetched
//                              instructions, land on correct target
//
// A global PASS/FAIL counter is accumulated across all groups.
// ================================================================

module tb_hazard_fwd;

// ── Clock / Reset ───────────────────────────────────────────────
reg clk, rst;
always #5 clk = ~clk;   // 10 ns period

// ── DUT ─────────────────────────────────────────────────────────
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

// ── Waveform dump ───────────────────────────────────────────────
initial begin
    $dumpfile("tb_hazard_fwd.vcd");
    $dumpvars(0, tb_hazard_fwd);
end

// ── Helpers ─────────────────────────────────────────────────────
integer pass_cnt, fail_cnt;

// NOP shorthand
`define NOP 32'h0000_0013

// Check macro: print result, count pass/fail
`define CHECK(label, got, exp) \
    if ((got) === (exp)) begin \
        $display("  PASS  %-30s  got=%0d", label, got); \
        pass_cnt = pass_cnt + 1; \
    end else begin \
        $display("  FAIL  %-30s  got=%0d  exp=%0d", label, got, exp); \
        fail_cnt = fail_cnt + 1; \
    end

// ── Task: flush all instruction memory to NOP ───────────────────
task flush_imem;
    integer k;
    begin
        for (k = 0; k < 64; k = k + 1)
            u_dut.u_imem.mem[k] = `NOP;
    end
endtask

// ── Task: do a hard reset (hold rst 3 cycles, release) ──────────
task do_reset;
    begin
        rst = 1;
        repeat(3) @(posedge clk);
        @(negedge clk); rst = 0;
    end
endtask

// ── Task: run N clock cycles ─────────────────────────────────────
task run_cycles;
    input integer n;
    integer i;
    begin
        for (i = 0; i < n; i = i + 1)
            @(posedge clk);
        #1; // small settle after last edge
    end
endtask

// ================================================================
// MAIN TEST SEQUENCE
// ================================================================
initial begin
    clk       = 0;
    rst       = 1;
    pass_cnt  = 0;
    fail_cnt  = 0;
    #20;

    // ============================================================
    // GROUP 1 – MEM→EX Forwarding
    // ────────────────────────────────────────────────────────────
    // The result of instruction N is consumed by instruction N+1
    // (one-cycle gap in the pipeline = EX/MEM → EX forward path).
    //
    // Program (no NOPs between dependent pairs):
    //   addi x1, x0, 7        → x1 = 7
    //   addi x1, x1, 3        → x1 = 10   ← MEM→EX fwd on x1
    //   addi x2, x1, 5        → x2 = 15   ← MEM→EX fwd on x1
    //   add  x3, x1, x2       → x3 = 25   ← MEM→EX fwd on x2
    //   (then NOPs to drain pipeline)
    // ============================================================
    $display("\n=== GROUP 1 : MEM->EX Forwarding ===");
    flush_imem;
    //                            slot  hex         comment
    u_dut.u_imem.mem[0]  = 32'h00700093; // addi x1, x0, 7
    u_dut.u_imem.mem[1]  = 32'h00308093; // addi x1, x1, 3   (uses x1 written above)
    u_dut.u_imem.mem[2]  = 32'h00508113; // addi x2, x1, 5   (uses new x1)
    u_dut.u_imem.mem[3]  = 32'h002081b3; // add  x3, x1, x2  (uses both)
    // slots 4-63 stay NOP (pipeline drain)
    do_reset;
    run_cycles(20);
    `CHECK("G1: x1 (expect 10)",  dbg_x1, 32'd10)
    `CHECK("G1: x2 (expect 15)",  dbg_x2, 32'd15)
    `CHECK("G1: x3 (expect 25)",  dbg_x3, 32'd25)

    // ============================================================
    // GROUP 2 – WB→EX Forwarding
    // ────────────────────────────────────────────────────────────
    // Instruction N+2 uses the result of instruction N
    // (two-cycle gap = MEM/WB → EX forward path).
    //
    //   addi x1, x0, 12       → x1 = 12
    //   addi x2, x0, 3        → x2 = 3   (independent)
    //   add  x3, x1, x2       → x3 = 15  ← WB→EX fwd on x1
    //   sub  x5, x3, x2       → x5 = 12  ← WB→EX fwd on x3
    // ============================================================
    $display("\n=== GROUP 2 : WB->EX Forwarding ===");
    flush_imem;
    u_dut.u_imem.mem[0]  = 32'h00c00093; // addi x1, x0, 12
    u_dut.u_imem.mem[1]  = 32'h00300113; // addi x2, x0, 3
    u_dut.u_imem.mem[2]  = 32'h002081b3; // add  x3, x1, x2
    u_dut.u_imem.mem[3]  = 32'h402182b3; // sub  x5, x3, x2
    do_reset;
    run_cycles(20);
    `CHECK("G2: x1 (expect 12)",  dbg_x1, 32'd12)
    `CHECK("G2: x2 (expect  3)",  dbg_x2, 32'd3)
    `CHECK("G2: x3 (expect 15)",  dbg_x3, 32'd15)
    `CHECK("G2: x5 (expect 12)",  dbg_x5, 32'd12)

    // ============================================================
    // GROUP 3 – Load-Use Stall  (Hazard Detection Unit)
    // ────────────────────────────────────────────────────────────
    // A load followed immediately by a use of its destination
    // register must stall for one cycle (HDU inserts bubble).
    //
    //   addi x1, x0, 0         → x1 = 0  (base address)
    //   sw   x0, 0(x1)         → mem[0] ← 0  (pre-clear)
    //   addi x2, x0, 42        → x2 = 42
    //   sw   x2, 0(x1)         → mem[0] ← 42
    //   lw   x3, 0(x1)         → x3 = 42  (load)
    //   add  x5, x3, x3        → x5 = 84  ← STALL: x3 not ready yet
    //   addi x6, x3, 1         → x6 = 43  ← second use after stall clears
    //
    // If stall is absent, x5 and x6 would receive stale (0) value.
    // ============================================================
    $display("\n=== GROUP 3 : Load-Use Stall (HDU) ===");
    flush_imem;
    u_dut.u_imem.mem[0]  = 32'h00000093; // addi x1, x0, 0
    u_dut.u_imem.mem[1]  = 32'h00008023; // sw   x0, 0(x1)
    u_dut.u_imem.mem[2]  = 32'h02a00113; // addi x2, x0, 42
    u_dut.u_imem.mem[3]  = 32'h00208023; // sw   x2, 0(x1)
    u_dut.u_imem.mem[4]  = 32'h00008183; // lw   x3, 0(x1)
    u_dut.u_imem.mem[5]  = 32'h003182b3; // add  x5, x3, x3  ← load-use hazard
    u_dut.u_imem.mem[6]  = 32'h00118313; // addi x6, x3, 1
    do_reset;
    run_cycles(30);
    `CHECK("G3: x3 (expect 42)",  dbg_x3, 32'd42)
    `CHECK("G3: x5 (expect 84)",  dbg_x5, 32'd84)
    `CHECK("G3: x6 (expect 43)",  dbg_x6, 32'd43)

    // ============================================================
    // GROUP 4 – Double Forwarding  (both rs1 and rs2 forwarded)
    // ────────────────────────────────────────────────────────────
    // Tests that ForwardA and ForwardB can both be non-zero in the
    // same cycle, each sourcing a different pipeline stage.
    //
    //   addi x1, x0, 6        → x1 = 6   (will be in MEM at cycle of add)
    //   addi x2, x0, 4        → x2 = 4   (will be in WB at cycle of add)
    //   add  x3, x1, x2       → x3 = 10  ← ForwardA=MEM(x1), ForwardB=WB(x2)
    //   sub  x5, x3, x2       → x5 = 6   ← ForwardA=MEM(x3), ForwardB=WB(x2)
    // ============================================================
    $display("\n=== GROUP 4 : Double Forwarding (both A and B) ===");
    flush_imem;
    u_dut.u_imem.mem[0]  = 32'h00600093; // addi x1, x0, 6
    u_dut.u_imem.mem[1]  = 32'h00400113; // addi x2, x0, 4
    u_dut.u_imem.mem[2]  = 32'h002081b3; // add  x3, x1, x2  ← double forward
    u_dut.u_imem.mem[3]  = 32'h402182b3; // sub  x5, x3, x2  ← double forward
    do_reset;
    run_cycles(20);
    `CHECK("G4: x1 (expect  6)",  dbg_x1, 32'd6)
    `CHECK("G4: x2 (expect  4)",  dbg_x2, 32'd4)
    `CHECK("G4: x3 (expect 10)",  dbg_x3, 32'd10)
    `CHECK("G4: x5 (expect  6)",  dbg_x5, 32'd6)

    // ============================================================
    // GROUP 5 – Branch Flush  (Hazard Detection Unit control flush)
    // ────────────────────────────────────────────────────────────
    // A taken beq must squash the two instructions fetched
    // speculatively after it and redirect PC to the target.
    //
    //   addi x1, x0, 5         → x1 = 5
    //   addi x2, x0, 5         → x2 = 5
    //   beq  x1, x2, +12       → branch TAKEN (offset=12 → skip next 2 words + land at mem[6])
    //   addi x3, x0, 99        ← must be SQUASHED  (would corrupt x3)
    //   addi x5, x0, 99        ← must be SQUASHED  (would corrupt x5)
    //   (target of beq, mem[6]):
    //   addi x6, x0, 77        → x6 = 77  ← correct path
    //
    // If the flush is absent, x3 and x5 would end up as 99.
    // ============================================================
    $display("\n=== GROUP 5 : Branch Flush (HDU control flush) ===");
    flush_imem;
    u_dut.u_imem.mem[0]  = 32'h00500093; // addi x1, x0, 5
    u_dut.u_imem.mem[1]  = 32'h00500113; // addi x2, x0, 5
    // beq x1, x2, +12  →  B-type, imm=12, rs1=x1, rs2=x2
    // encoding: imm[12|10:5] rs2 rs1 000 imm[4:1|11] 1100011
    // imm=12=0b00001100 → imm[12]=0 imm[11]=0 imm[10:5]=000001 imm[4:1]=1000
    // Full: 0_000001_00010_00001_000_1000_0_1100011 = 32'h00208663
    u_dut.u_imem.mem[2]  = 32'h00208663; // beq x1, x2, +12  (target = PC+12 = mem[5])
    u_dut.u_imem.mem[3]  = 32'h06300193; // addi x3, x0, 99  ← SQUASH
    u_dut.u_imem.mem[4]  = 32'h06300293; // addi x5, x0, 99  ← SQUASH
    u_dut.u_imem.mem[5]  = 32'h04d00313; // addi x6, x0, 77  ← branch target
    do_reset;
    run_cycles(30);
    `CHECK("G5: x1 (expect  5)",   dbg_x1, 32'd5)
    `CHECK("G5: x2 (expect  5)",   dbg_x2, 32'd5)
    `CHECK("G5: x3 (expect  0)",   dbg_x3, 32'd0)  // squashed, never written
    `CHECK("G5: x5 (expect  0)",   dbg_x5, 32'd0)  // squashed, never written
    `CHECK("G5: x6 (expect 77)",   dbg_x6, 32'd77) // landed on target correctly

    // ============================================================
    // FINAL SUMMARY
    // ============================================================
    $display("\n╔══════════════════════════════════════════════╗");
    $display("║          SIMULATION COMPLETE                 ║");
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

// ── Optional pipeline monitor (comment out if noisy) ────────────
always @(posedge clk) begin
    #1;
    $display("t=%0t  PC=%h  FwdA=%b FwdB=%b  stall=%b  flushDE=%b",
        $time,
        dbg_pc,
        u_dut.u_fwd.ForwardA,
        u_dut.u_fwd.ForwardB,
        u_dut.u_hazard.stall_pc,
        u_dut.u_hazard.flush_id_ex);
end

initial begin
    $dumpfile("tb_hazard_fwd.vcd");   // name of waveform file
    $dumpvars(0, tb_hazard_fwd);      // dump all signals inside tb_hazard_fwd
end


endmodule
