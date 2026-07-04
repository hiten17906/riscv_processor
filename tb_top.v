`timescale 1ns/1ps

module tb_top;

// ── Clk / Rst ──────────────────────────────────────────────
reg clk;
reg rst;

// ── Loop variable at MODULE level (required by Verilog) ────
integer fill_i;

// ── DUT ────────────────────────────────────────────────────
wire [31:0] dbg_pc, dbg_if_instr, dbg_id_instr;
wire [31:0] dbg_x1, dbg_x2, dbg_x3, dbg_x5, dbg_x6;
wire [31:0] dbg_x7, dbg_x8, dbg_x9, dbg_x10, dbg_x11;
wire [31:0] dbg_x12, dbg_x16, dbg_x17;
wire [31:0] dbg_dm0, dbg_dm1, dbg_dm2;

top u_dut (
    .clk         (clk),
    .rst         (rst),
    .dbg_pc      (dbg_pc),
    .dbg_if_instr(dbg_if_instr),
    .dbg_id_instr(dbg_id_instr),
    .dbg_x1      (dbg_x1),
    .dbg_x2      (dbg_x2),
    .dbg_x3      (dbg_x3),
    .dbg_x5      (dbg_x5),
    .dbg_x6      (dbg_x6),
    .dbg_x7      (dbg_x7),
    .dbg_x8      (dbg_x8),
    .dbg_x9      (dbg_x9),
    .dbg_x10     (dbg_x10),
    .dbg_x11     (dbg_x11),
    .dbg_x12     (dbg_x12),
    .dbg_x16     (dbg_x16),
    .dbg_x17     (dbg_x17),
    .dbg_dm0     (dbg_dm0),
    .dbg_dm1     (dbg_dm1),
    .dbg_dm2     (dbg_dm2)
);

// ── Clock generation ───────────────────────────────────────
always #5 clk = ~clk;

// ── Program load + reset ───────────────────────────────────
initial begin
    clk = 0;
    rst = 1;
    #20;
    rst = 0;

    // ---- initialise registers ----
    u_dut.u_imem.mem[0]  = 32'h00a00093; // addi x1, x0, 10
    u_dut.u_imem.mem[1]  = 32'h00000013; // nop
    u_dut.u_imem.mem[2]  = 32'h00000013; // nop
    u_dut.u_imem.mem[3]  = 32'h00000013; // nop

    u_dut.u_imem.mem[4]  = 32'h01400113; // addi x2, x0, 20
    u_dut.u_imem.mem[5]  = 32'h00000013;
    u_dut.u_imem.mem[6]  = 32'h00000013;
    u_dut.u_imem.mem[7]  = 32'h00000013;

    u_dut.u_imem.mem[8]  = 32'h00500193; // addi x3, x0, 5
    u_dut.u_imem.mem[9]  = 32'h00000013;
    u_dut.u_imem.mem[10] = 32'h00000013;
    u_dut.u_imem.mem[11] = 32'h00000013;

    // ---- R-type ALU ops ----
    u_dut.u_imem.mem[12] = 32'h002082b3; // add x5, x1, x2   → 30
    u_dut.u_imem.mem[13] = 32'h00000013;
    u_dut.u_imem.mem[14] = 32'h00000013;
    u_dut.u_imem.mem[15] = 32'h00000013;

    u_dut.u_imem.mem[16] = 32'h40310333; // sub x6, x2, x3   → 15
    u_dut.u_imem.mem[17] = 32'h00000013;
    u_dut.u_imem.mem[18] = 32'h00000013;
    u_dut.u_imem.mem[19] = 32'h00000013;

    u_dut.u_imem.mem[20] = 32'h0030f3b3; // and x7, x1, x3   → 0
    u_dut.u_imem.mem[21] = 32'h00000013;
    u_dut.u_imem.mem[22] = 32'h00000013;
    u_dut.u_imem.mem[23] = 32'h00000013;

    u_dut.u_imem.mem[24] = 32'h0030e433; // or  x8, x1, x3   → 15
    u_dut.u_imem.mem[25] = 32'h00000013;
    u_dut.u_imem.mem[26] = 32'h00000013;
    u_dut.u_imem.mem[27] = 32'h00000013;

    // ---- I-type ops ----
    u_dut.u_imem.mem[28] = 32'h01f2f493; // andi x9,  x5, 31  → 30
    u_dut.u_imem.mem[29] = 32'h00000013;
    u_dut.u_imem.mem[30] = 32'h00000013;
    u_dut.u_imem.mem[31] = 32'h00000013;

    u_dut.u_imem.mem[32] = 32'h00136513; // ori  x10, x6, 1   → 15
    u_dut.u_imem.mem[33] = 32'h00000013;
    u_dut.u_imem.mem[34] = 32'h00000013;
    u_dut.u_imem.mem[35] = 32'h00000013;

    u_dut.u_imem.mem[36] = 32'h0011a5b3; // slt  x11, x3, x1  → 1
    u_dut.u_imem.mem[37] = 32'h00000013;
    u_dut.u_imem.mem[38] = 32'h00000013;
    u_dut.u_imem.mem[39] = 32'h00000013;

    u_dut.u_imem.mem[40] = 32'h0641a613; // slti x12, x3, 100 → 1
    u_dut.u_imem.mem[41] = 32'h00000013;
    u_dut.u_imem.mem[42] = 32'h00000013;
    u_dut.u_imem.mem[43] = 32'h00000013;

    // ---- Store ----
    u_dut.u_imem.mem[44] = 32'h00122023; // sw x1, 0(x4)
    u_dut.u_imem.mem[45] = 32'h00000013;
    u_dut.u_imem.mem[46] = 32'h00000013;
    u_dut.u_imem.mem[47] = 32'h00000013;

    u_dut.u_imem.mem[48] = 32'h00222223; // sw x2, 4(x4)
    u_dut.u_imem.mem[49] = 32'h00000013;
    u_dut.u_imem.mem[50] = 32'h00000013;
    u_dut.u_imem.mem[51] = 32'h00000013;

    u_dut.u_imem.mem[52] = 32'h00522423; // sw x5, 8(x4)
    u_dut.u_imem.mem[53] = 32'h00000013;
    u_dut.u_imem.mem[54] = 32'h00000013;
    u_dut.u_imem.mem[55] = 32'h00000013;

    // ---- Load ----
    u_dut.u_imem.mem[56] = 32'h00022803; // lw x16, 0(x4)
    u_dut.u_imem.mem[57] = 32'h00000013;
    u_dut.u_imem.mem[58] = 32'h00000013;
    u_dut.u_imem.mem[59] = 32'h00000013;

    // ---- Final add ----
    u_dut.u_imem.mem[60] = 32'h002808b3; // add x17, x16, x2  → 30
    u_dut.u_imem.mem[61] = 32'h00000013;
    u_dut.u_imem.mem[62] = 32'h00000013;
    u_dut.u_imem.mem[63] = 32'h00000013;
end

// ── Pipeline monitor ───────────────────────────────────────
always @(posedge clk) begin
    #1;
    $display("t=%0t | PC=%h | IF=%h | ID=%h",
            $time, dbg_pc, dbg_if_instr, dbg_id_instr);
end

// ── End-of-sim checker ─────────────────────────────────────
initial begin
    #565000;

    $display("\n========== REGISTER FILE CONTENTS ==========");
    $display("x1  (expect 10) = %0d", dbg_x1);
    $display("x2  (expect 20) = %0d", dbg_x2);
    $display("x3  (expect  5) = %0d", dbg_x3);
    $display("x5  (expect 30) = %0d", dbg_x5);
    $display("x6  (expect 15) = %0d", dbg_x6);
    $display("x7  (expect  0) = %0d", dbg_x7);
    $display("x8  (expect 15) = %0d", dbg_x8);
    $display("x9  (expect 30) = %0d", dbg_x9);
    $display("x10 (expect 15) = %0d", dbg_x10);
    $display("x11 (expect  1) = %0d", dbg_x11);
    $display("x12 (expect  1) = %0d", dbg_x12);
    $display("x16 (expect 10) = %0d", dbg_x16);
    $display("x17 (expect 30) = %0d", dbg_x17);

    $display("\n========== DATA MEMORY CONTENTS ==========");
    $display("mem[0] (expect 10) = %0d", dbg_dm0);
    $display("mem[1] (expect 20) = %0d", dbg_dm1);
    $display("mem[2] (expect 30) = %0d", dbg_dm2);

    $display("\n========== PASS / FAIL ==========");
    $display("x1  %s", (dbg_x1  == 32'd10) ? "PASS" : "FAIL");
    $display("x2  %s", (dbg_x2  == 32'd20) ? "PASS" : "FAIL");
    $display("x3  %s", (dbg_x3  == 32'd5 ) ? "PASS" : "FAIL");
    $display("x5  %s", (dbg_x5  == 32'd30) ? "PASS" : "FAIL");
    $display("x6  %s", (dbg_x6  == 32'd15) ? "PASS" : "FAIL");
    $display("x7  %s", (dbg_x7  == 32'd0 ) ? "PASS" : "FAIL");
    $display("x8  %s", (dbg_x8  == 32'd15) ? "PASS" : "FAIL");
    $display("x9  %s", (dbg_x9  == 32'd30) ? "PASS" : "FAIL");
    $display("x10 %s", (dbg_x10 == 32'd15) ? "PASS" : "FAIL");
    $display("x11 %s", (dbg_x11 == 32'd1 ) ? "PASS" : "FAIL");
    $display("x12 %s", (dbg_x12 == 32'd1 ) ? "PASS" : "FAIL");
    $display("x16 %s", (dbg_x16 == 32'd10) ? "PASS" : "FAIL");
    $display("x17 %s", (dbg_x17 == 32'd30) ? "PASS" : "FAIL");
    $display("dm0 %s", (dbg_dm0 == 32'd10) ? "PASS" : "FAIL");
    $display("dm1 %s", (dbg_dm1 == 32'd20) ? "PASS" : "FAIL");
    $display("dm2 %s", (dbg_dm2 == 32'd30) ? "PASS" : "FAIL");

    $finish;
end

initial begin
    $dumpfile("tb_top.vcd");   // name of waveform file
    $dumpvars(0, tb_top);      // dump all signals inside tb_top
end

endmodule
