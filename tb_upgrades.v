`timescale 1ns/1ps
// =================================================================
// tb_upgrades.v  –  Testbench for the Four Advanced CPU Upgrades
//                   (Branch Prediction, RV32M, CSRs, L1 Cache)
// =================================================================
`include "top.v"

module tb_upgrades;

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

    // NOP shorthand
    `define NOP 32'h0000_0013

    task flush_imem;
        integer k;
        begin
            for (k = 0; k < 64; k = k + 1)
                u_dut.u_imem.mem[k] = `NOP;
        end
    endtask

    task do_reset;
        begin
            rst = 1;
            repeat(5) @(posedge clk);
            @(negedge clk); rst = 0;
        end
    endtask

    task run_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1)
                @(posedge clk);
            #1; // settle
        end
    endtask

    // Pipeline monitor
    always @(posedge clk) begin
        if (!rst) begin
            $display("t=%0t | PC=%h | IF_instr=%h | ID_instr=%h | icache_stall=%b dcache_stall=%b | stall_pc=%b",
                $time, u_dut.pc_current, u_dut.if_instr, u_dut.id_instr, u_dut.icache_stall, u_dut.dcache_stall, u_dut.stall_pc);
        end
    end

    initial begin
        clk = 0;
        rst = 1;
        #20;

        // ============================================================
        // TEST 1: RV32M (Multiplier and Divider)
        // ────────────────────────────────────────────────────────────
        //   addi x1, x0, 10
        //   addi x2, x0, 3
        //   mul  x5, x1, x2       # x5 = 10 * 3 = 30
        //   div  x6, x1, x2       # x6 = 10 / 3 = 3
        //   rem  x7, x1, x2       # x7 = 10 % 3 = 1
        // ============================================================
        $display("\n=== TEST 1: RV32M Multiplier and Divider ===");
        flush_imem;
        u_dut.u_imem.mem[0]  = 32'h00a00093; // addi x1, x0, 10
        u_dut.u_imem.mem[1]  = 32'h00300113; // addi x2, x0, 3
        // R-type mul: rs1=x1, rs2=x2, rd=x5, funct3=000, funct7=0000001
        // 0000001_00010_00001_000_00101_0110011 = 022082b3
        u_dut.u_imem.mem[2]  = 32'h022082b3; // mul x5, x1, x2
        // R-type div: rs1=x1, rs2=x2, rd=x6, funct3=100, funct7=0000001
        // 0000001_00010_00001_100_00110_0110011 = 0220c333
        u_dut.u_imem.mem[3]  = 32'h0220c333; // div x6, x1, x2
        // R-type rem: rs1=x1, rs2=x2, rd=x7, funct3=110, funct7=0000001
        // 0000001_00010_00001_110_00111_0110011 = 0220e3b3
        u_dut.u_imem.mem[4]  = 32'h0220e3b3; // rem x7, x1, x2
        do_reset;
        run_cycles(100);
        `CHECK("T1: mul  x5 (expect 30)", dbg_x5, 32'd30)
        `CHECK("T1: div  x6 (expect  3)", dbg_x6, 32'd3)
        `CHECK("T1: rem  x7 (expect  1)", dbg_x7, 32'd1)

        // ============================================================
        // TEST 2: CSR Registers & Trap (ecall)
        // ────────────────────────────────────────────────────────────
        //   addi x1, x0, 48
        //   csrrw x0, mtvec, x1   # Set mtvec trap address to 48 = mem[12]
        //   nop                   # Gaps to let CSR write propagate to WB
        //   nop
        //   nop
        //   ecall                 # Trap! PC should jump to 48 (mem[12])
        //   addi x2, x0, 99       # Squashed!
        //   ...
        //   mem[12] (trap handler):
        //   addi x3, x0, 5        # Trap handler executes!
        // ============================================================
        $display("\n=== TEST 2: CSR Instructions & Exception Trap ===");
        flush_imem;
        u_dut.u_imem.mem[0]  = 32'h03000093; // addi x1, x0, 48
        u_dut.u_imem.mem[1]  = 32'h30509073; // csrrw x0, mtvec, x1 (mtvec = 48 = 0x30 = mem[12])
        u_dut.u_imem.mem[2]  = `NOP;
        u_dut.u_imem.mem[3]  = `NOP;
        u_dut.u_imem.mem[4]  = `NOP;
        u_dut.u_imem.mem[5]  = 32'h00000073; // ecall (Trap!) at PC = 20
        u_dut.u_imem.mem[6]  = 32'h06300113; // addi x2, x0, 99 -- SQUASHED
        u_dut.u_imem.mem[7]  = 32'h00000013; // NOP
        
        // Trap handler at mem[12] (PC = 48 = 0x30)
        u_dut.u_imem.mem[12] = 32'h00500193; // addi x3, x0, 5  -- Handler executes
        do_reset;
        run_cycles(100);
        `CHECK("T2: mtvec check (expect 48)", u_dut.u_csr.mtvec, 32'd48)
        `CHECK("T2: mepc check (expect 20)",  u_dut.u_csr.mepc,  32'd20) // ecall was at PC=20
        `CHECK("T2: mcause check (expect 11)", u_dut.u_csr.mcause, 32'd11) // ecall code
        `CHECK("T2: x2 squashed (expect 0)",  dbg_x2, 32'd0)
        `CHECK("T2: x3 handler (expect 5)",   dbg_x3, 32'd5)

        // ============================================================
        // TEST 3: Dynamic Branch Prediction (BTB / BHT)
        // ────────────────────────────────────────────────────────────
        //   addi x1, x0, 5
        //   addi x2, x0, 5
        //   Loop:
        //   beq  x1, x2, Target   # 1st run: predicted NOT taken (miss). Resolves TAKEN. Updates BTB.
        //   addi x3, x0, 88       # Squashed on 1st run.
        //   Target:
        //   addi x3, x0, 1        # executes
        //   beq  x1, x2, Loop     # 2nd run: predicted TAKEN (hit!). 0-cycle redirect penalty.
        // ============================================================
        $display("\n=== TEST 3: Dynamic Branch Prediction ===");
        flush_imem;
        u_dut.u_imem.mem[0]  = 32'h00500093; // addi x1, x0, 5
        u_dut.u_imem.mem[1]  = 32'h00500113; // addi x2, x0, 5
        // beq x1, x2, +12 (target = PC+12 = mem[5])
        u_dut.u_imem.mem[2]  = 32'h00208663; // beq x1, x2, +12
        u_dut.u_imem.mem[3]  = 32'h05800193; // addi x3, x0, 88 -- SQUASHED (1st run)
        u_dut.u_imem.mem[4]  = 32'h00000013; // NOP
        u_dut.u_imem.mem[5]  = 32'h00100193; // addi x3, x0, 1  -- target
        u_dut.u_imem.mem[6]  = 32'hfe208ae3; // beq x1, x2, -12 (loop target = mem[2])
        u_dut.u_imem.mem[7]  = 32'h00000013; // NOP
        u_dut.u_imem.mem[8]  = 32'h00000013; // NOP
        do_reset;
        // Run long enough to verify the loop and branch prediction hits
        run_cycles(100);
        `CHECK("T3: Loop ran successfully, x3 (expect 1)", dbg_x3, 32'd1)
        // The BTB should be valid for the branch at index 2
        `CHECK("T3: BTB valid for mem[2] branch", u_dut.u_bp.btb_valid[2], 1'b1)
        `CHECK("T3: BTB target for mem[2] branch (expect 20)", u_dut.u_bp.btb_target[2], 32'd20)

        // ============================================================
        // FINAL SUMMARY
        // ============================================================
        $display("\n╔══════════════════════════════════════════════╗");
        $display("║          UPGRADES SIMULATION COMPLETE        ║");
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
