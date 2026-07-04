`timescale 1ns/1ps
// =================================================================
// tb_soc.v  –  SoC Mode Verification (UART & Timer)
// =================================================================
`include "top.v"

module tb_soc;

    reg clk;
    reg rst;

    // DUT Taps
    wire [31:0] dbg_pc;
    wire [31:0] dbg_x6;

    top u_dut (
        .clk          (clk),
        .rst          (rst),
        .dbg_pc       (dbg_pc),
        .dbg_x6       (dbg_x6)
    );

    // Clock generator: 10 ns period
    always #5 clk = ~clk;

    integer k;

    initial begin
        $display("\n=====================================================");
        $display("          RISC-V SOC MODE PRINT TEST");
        $display("=====================================================");

        clk = 0;
        rst = 1;

        // Load the UART printing and Timer read program:
        // PC 0:   addi x4, x0, 1024     (x4 = 1024)
        // PC 4:   add  x4, x4, x4       (x4 = 2048)
        // PC 8:   add  x4, x4, x4       (x4 = 4096)
        // PC 12:  add  x4, x4, x4       (x4 = 8192 = 0x00002000)
        // PC 16:  addi x5, x0, 82       ('R')
        // PC 20:  sw x5, 0(x4)          (write UART)
        // PC 24:  addi x5, x0, 73       ('I')
        // PC 28:  sw x5, 0(x4)          (write UART)
        // PC 32:  addi x5, x0, 83       ('S')
        // PC 36:  sw x5, 0(x4)          (write UART)
        // PC 40:  addi x5, x0, 67       ('C')
        // PC 44:  sw x5, 0(x4)          (write UART)
        // PC 48:  addi x5, x0, 45       ('-')
        // PC 52:  sw x5, 0(x4)          (write UART)
        // PC 56:  addi x5, x0, 86       ('V')
        // PC 60:  sw x5, 0(x4)          (write UART)
        // PC 64:  addi x5, x0, 32       (' ')
        // PC 68:  sw x5, 0(x4)          (write UART)
        // PC 72:  addi x5, x0, 83       ('S')
        // PC 76:  sw x5, 0(x4)          (write UART)
        // PC 80:  addi x5, x0, 79       ('O')
        // PC 84:  sw x5, 0(x4)          (write UART)
        // PC 88:  addi x5, x0, 67       ('C')
        // PC 92:  sw x5, 0(x4)          (write UART)
        // PC 96:  addi x5, x0, 32       (' ')
        // PC 100: sw x5, 0(x4)          (write UART)
        // PC 104: addi x5, x0, 79       ('O')
        // PC 108: sw x5, 0(x4)          (write UART)
        // PC 112: addi x5, x0, 75       ('K')
        // PC 116: sw x5, 0(x4)          (write UART)
        // PC 120: addi x5, x0, 10       ('\n')
        // PC 124: sw x5, 0(x4)          (write UART)
        // PC 128: lw x6, 8(x4)          (read Timer from 0x00002008)
        // PC 132: jal x0, 0             (halt self-loop)

        u_dut.u_imem.mem[0]  = 32'h40000213;
        u_dut.u_imem.mem[1]  = 32'h00420233;
        u_dut.u_imem.mem[2]  = 32'h00420233;
        u_dut.u_imem.mem[3]  = 32'h00420233;
        u_dut.u_imem.mem[4]  = 32'h05200293;
        u_dut.u_imem.mem[5]  = 32'h00522023;
        u_dut.u_imem.mem[6]  = 32'h04900293;
        u_dut.u_imem.mem[7]  = 32'h00522023;
        u_dut.u_imem.mem[8]  = 32'h05300293;
        u_dut.u_imem.mem[9]  = 32'h00522023;
        u_dut.u_imem.mem[10] = 32'h04300293;
        u_dut.u_imem.mem[11] = 32'h00522023;
        u_dut.u_imem.mem[12] = 32'h02d00293;
        u_dut.u_imem.mem[13] = 32'h00522023;
        u_dut.u_imem.mem[14] = 32'h05600293;
        u_dut.u_imem.mem[15] = 32'h00522023;
        u_dut.u_imem.mem[16] = 32'h02000293;
        u_dut.u_imem.mem[17] = 32'h00522023;
        u_dut.u_imem.mem[18] = 32'h05300293;
        u_dut.u_imem.mem[19] = 32'h00522023;
        u_dut.u_imem.mem[20] = 32'h04f00293;
        u_dut.u_imem.mem[21] = 32'h00522023;
        u_dut.u_imem.mem[22] = 32'h04300293;
        u_dut.u_imem.mem[23] = 32'h00522023;
        u_dut.u_imem.mem[24] = 32'h02000293;
        u_dut.u_imem.mem[25] = 32'h00522023;
        u_dut.u_imem.mem[26] = 32'h04f00293;
        u_dut.u_imem.mem[27] = 32'h00522023;
        u_dut.u_imem.mem[28] = 32'h04b00293;
        u_dut.u_imem.mem[29] = 32'h00522023;
        u_dut.u_imem.mem[30] = 32'h00a00293;
        u_dut.u_imem.mem[31] = 32'h00522023;
        u_dut.u_imem.mem[32] = 32'h00822303;
        u_dut.u_imem.mem[33] = 32'h0000006f;

        // Fill remaining instruction memory with NOPs
        for (k = 34; k < 64; k = k + 1) begin
            u_dut.u_imem.mem[k] = 32'h00000013;
        end

        // Reset Sequence
        #10;
        rst = 1;
        repeat(5) @(posedge clk);
        @(negedge clk); rst = 0;

        // Run until JAL self-loop is hit at WB stage
        // Halt PC = 132 (33 * 4 = 132)
        while ((u_dut.wb_pc_plus4 - 4) !== 32'd132) begin
            @(posedge clk);
        end

        // Wait a few cycles to clear pipeline
        repeat(5) @(posedge clk);

        // Verification Results
        $display("\n=====================================================");
        $display("          VERIFICATION RESULTS");
        $display("=====================================================");
        if (dbg_x6 > 0) begin
            $display("  PASS: System Timer value read successfully: %d cycles", dbg_x6);
            $display("  RESULT: SUCCESS ✓");
        end else begin
            $display("  FAIL: System Timer value was 0");
            $display("  RESULT: FAILED ✗");
        end
        $display("=====================================================\n");
        $finish;
    end

endmodule
