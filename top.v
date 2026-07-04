// ============================================================
// top.v  –  Upgraded 5-Stage Pipelined RISC-V Processor
//           With Branch Prediction, RV32M, CSRs, and L1 Cache.
// ============================================================
`include "pc.v"
`include "instr_mem.v"
`include "if_id_reg.v"
`include "control.v"
`include "reg_file.v"
`include "imm_gen.v"
`include "id_ex_reg.v"
`include "alu_control.v"
`include "alu.v"
`include "ex_mem_reg.v"
`include "data_mem.v"
`include "mem_wb_reg.v"
`include "hazard_unit.v"
`include "forwarding_unit.v"
`include "branch_predictor.v"
`include "mult_div.v"
`include "csr_file.v"
`include "cache_controller.v"

module top (
    input  wire clk,
    input  wire rst,

    // Debug outputs for testbench
    output wire [31:0] dbg_pc,
    output wire [31:0] dbg_if_instr,
    output wire [31:0] dbg_id_instr,

    output wire [31:0] dbg_x1,
    output wire [31:0] dbg_x2,
    output wire [31:0] dbg_x3,
    output wire [31:0] dbg_x5,
    output wire [31:0] dbg_x6,
    output wire [31:0] dbg_x7,
    output wire [31:0] dbg_x8,
    output wire [31:0] dbg_x9,
    output wire [31:0] dbg_x10,
    output wire [31:0] dbg_x11,
    output wire [31:0] dbg_x12,
    output wire [31:0] dbg_x16,
    output wire [31:0] dbg_x17,

    output wire [31:0] dbg_dm0,
    output wire [31:0] dbg_dm1,
    output wire [31:0] dbg_dm2
);

// ===========================================================
// IF STAGE
// ===========================================================
    wire [31:0] pc_current, pc_next, if_instr;
    wire [31:0] final_mem_read_data;
    wire [31:0] mem_forward_data;
    wire        jump_mem;
    wire [31:0] branch_target_mem;

    // Hazard / stall signals (driven by hazard_unit below)
    wire stall_pc, stall_if_id, stall_id_ex, stall_ex_mem, stall_mem_wb;
    wire flush_if_id, flush_id_ex, flush_ex_mem, flush_mem_wb;

    // Branch predictor signals
    wire        pred_taken;
    wire [31:0] pred_target;

    // Mispredict and Trap resolution from ID stage
    wire        id_mispredict;
    wire [31:0] id_mispredict_target;
    wire        id_trap_en;
    wire [31:0] mtvec_out;

    // PC next-value logic with dynamic predictor & mispredict/trap correction
    assign pc_next = id_trap_en   ? mtvec_out :
                     stall_pc      ? pc_current :
                     id_mispredict ? id_mispredict_target :
                     pred_taken    ? pred_target :
                                     pc_current + 32'd4;

    pc u_pc (
        .clk(clk), .rst(rst),
        .pc_next(pc_next), .pc_out(pc_current)
    );

    // L1 Instruction Cache
    wire        icache_stall;
    wire        imem_read, imem_write;
    wire [31:0] imem_addr, imem_wdata, imem_rdata;

    cache_controller u_icache (
        .clk      (clk),
        .rst      (rst),
        .cpu_read (1'b1),
        .cpu_write(1'b0),
        .cpu_addr (pc_current),
        .cpu_wdata(32'b0),
        .cpu_rdata(if_instr),
        .cpu_stall(icache_stall),
        .mem_read (imem_read),
        .mem_write(imem_write),
        .mem_addr (imem_addr),
        .mem_wdata(imem_wdata),
        .mem_rdata(imem_rdata)
    );

    instr_mem u_imem (
        .clk  (clk),
        .addr (imem_addr),
        .instr(imem_rdata)
    );

    assign dbg_pc       = pc_current;
    assign dbg_if_instr = if_instr;

// ===========================================================
// IF/ID REGISTER
// ===========================================================
    reg [31:0] if_id_pc_r, if_id_instr_r;
    reg        if_id_pred_taken;
    reg [31:0] if_id_pred_target;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            if_id_pc_r        <= 32'b0;
            if_id_instr_r     <= 32'h00000013; // NOP
            if_id_pred_taken  <= 1'b0;
            if_id_pred_target <= 32'b0;
        end else if (flush_if_id) begin
            if_id_pc_r        <= 32'b0;
            if_id_instr_r     <= 32'h00000013;
            if_id_pred_taken  <= 1'b0;
            if_id_pred_target <= 32'b0;
        end else if (!stall_if_id) begin
            if_id_pc_r        <= pc_current;
            if_id_instr_r     <= if_instr;
            if_id_pred_taken  <= pred_taken;
            if_id_pred_target <= pred_target;
        end
    end

    wire [31:0] id_pc          = if_id_pc_r;
    wire [31:0] id_instr       = if_id_instr_r;
    wire        id_pred_taken  = if_id_pred_taken;
    wire [31:0] id_pred_target = if_id_pred_target;

    assign dbg_id_instr = id_instr;

// ===========================================================
// ID STAGE
// ===========================================================
    wire [6:0] id_opcode   = id_instr[6:0];
    wire [4:0] id_rd       = id_instr[11:7];
    wire [2:0] id_funct3   = id_instr[14:12];
    wire [4:0] id_rs1      = id_instr[19:15];
    wire [4:0] id_rs2      = id_instr[24:20];
    wire       id_funct7_5 = id_instr[30];
    wire       id_funct7_0 = id_instr[25];

    wire id_RegWrite, id_MemRead, id_MemWrite, id_MemToReg;
    wire id_ALUSrc, id_Branch, id_Jump;
    wire [1:0] id_ALUOp;

    wire [1:0]  id_csr_op;
    wire        id_csr_sel;
    wire [31:0] id_trap_cause;

    control u_ctrl (
        .opcode(id_opcode), .funct3(id_funct3), .funct12(id_instr[31:20]),
        .RegWrite(id_RegWrite), .MemRead(id_MemRead),
        .MemWrite(id_MemWrite), .MemToReg(id_MemToReg),
        .ALUSrc(id_ALUSrc), .Branch(id_Branch),
        .Jump(id_Jump), .ALUOp(id_ALUOp),
        .csr_op(id_csr_op), .csr_sel(id_csr_sel),
        .trap_en(id_trap_en), .trap_cause(id_trap_cause)
    );

    wire        wb_RegWrite;
    wire [4:0]  wb_rd;
    wire [31:0] wb_write_data;
    wire [31:0] id_read_data1, id_read_data2;

    reg_file u_regfile (
        .clk(clk), .rst(rst), .RegWrite(wb_RegWrite),
        .rs1(id_rs1), .rs2(id_rs2),
        .rd(wb_rd), .write_data(wb_write_data),
        .read_data1(id_read_data1), .read_data2(id_read_data2)
    );

    wire [31:0] id_imm;
    imm_gen u_immgen (.instr(id_instr), .imm_out(id_imm));

    // MEM and WB stage wires (needed for ID forwarding)
    wire [4:0]  mem_rd;
    wire        mem_RegWrite;
    wire [31:0] mem_alu_result;
    wire [31:0] wb_alu_result;

    // MEM-stage forwarding data selector (handles load-to-use forwarding from MEM stage)
    assign mem_forward_data = mem_MemToReg ? final_mem_read_data : mem_alu_result;

    // ── ID Forwarding Muxes (for branch comparison & JALR target) ──
    wire [31:0] id_val1 = (mem_RegWrite && (mem_rd != 5'b0) && (mem_rd == id_rs1)) ? mem_forward_data :
                          (wb_RegWrite  && (wb_rd  != 5'b0) && (wb_rd  == id_rs1)) ? wb_write_data  :
                                                                                     id_read_data1;

    wire [31:0] id_val2 = (mem_RegWrite && (mem_rd != 5'b0) && (mem_rd == id_rs2)) ? mem_forward_data :
                          (wb_RegWrite  && (wb_rd  != 5'b0) && (wb_rd  == id_rs2)) ? wb_write_data  :
                                                                                     id_read_data2;

    // ── ID Branch comparison ─────────────────────────────────────────
    reg id_branch_taken;
    always @(*) begin
        case (id_funct3)
            3'b000: id_branch_taken = (id_val1 == id_val2);             // beq
            3'b001: id_branch_taken = (id_val1 != id_val2);             // bne
            3'b100: id_branch_taken = ($signed(id_val1) < $signed(id_val2)); // blt
            3'b101: id_branch_taken = ($signed(id_val1) >= $signed(id_val2));// bge
            3'b110: id_branch_taken = (id_val1 < id_val2);              // bltu
            3'b111: id_branch_taken = (id_val1 >= id_val2);             // bgeu
            default: id_branch_taken = 1'b0;
        endcase
    end

    wire id_take_branch = id_Branch && id_branch_taken;
    wire id_redirect    = id_take_branch || id_Jump;

    // Branch/jump target calculation in ID stage
    wire [31:0] id_branch_target = (id_opcode == 7'b1100111) ? (id_val1 + id_imm) & 32'hfffffffe :
                                                               (id_pc + id_imm);

    // Predictor Mispredict Evaluation
    assign id_mispredict = (id_Branch || id_Jump) && 
                           ((id_redirect != id_pred_taken) || 
                            (id_redirect && (id_branch_target != id_pred_target)));

    assign id_mispredict_target = id_redirect ? id_branch_target : (id_pc + 32'd4);

    // Update branch predictor on branch resolved in ID
    branch_predictor u_bp (
        .clk          (clk),
        .rst          (rst),
        .fetch_pc     (pc_current),
        .pred_taken   (pred_taken),
        .pred_target  (pred_target),
        .update_en    ((id_Branch || id_Jump) && !stall_if_id),
        .update_pc    (id_pc),
        .update_taken (id_redirect),
        .update_target(id_branch_target)
    );

// ===========================================================
// ID/EX REGISTER
// ===========================================================
    wire        ex_RegWrite, ex_MemRead, ex_MemWrite, ex_MemToReg;
    wire        ex_ALUSrc, ex_Branch, ex_Jump;
    wire [1:0]  ex_ALUOp;
    wire [1:0]  ex_csr_op;
    wire        ex_csr_sel;
    wire [31:0] ex_pc, ex_read_data1, ex_read_data2, ex_imm;
    wire [4:0]  ex_rs1, ex_rs2, ex_rd;
    wire [2:0]  ex_funct3;
    wire        ex_funct7_5;
    wire        ex_funct7_0;
    wire [6:0]  ex_opcode;
    wire [11:0] ex_csr_addr;

    id_ex_reg u_id_ex (
        .clk(clk), .rst(rst), .stall(stall_id_ex), .flush(flush_id_ex),
        .in_RegWrite(id_RegWrite), .in_MemRead(id_MemRead),
        .in_MemWrite(id_MemWrite), .in_MemToReg(id_MemToReg),
        .in_ALUSrc(id_ALUSrc), .in_Branch(id_Branch),
        .in_Jump(id_Jump), .in_ALUOp(id_ALUOp),
        .in_csr_op(id_csr_op), .in_csr_sel(id_csr_sel),
        .in_pc(id_pc), .in_read_data1(id_read_data1),
        .in_read_data2(id_read_data2), .in_imm(id_imm),
        .in_rs1(id_rs1), .in_rs2(id_rs2), .in_rd(id_rd),
        .in_funct3(id_funct3), .in_funct7_5(id_funct7_5), .in_funct7_0(id_funct7_0),
        .in_opcode(id_opcode), .in_csr_addr(id_instr[31:20]),
        .out_RegWrite(ex_RegWrite), .out_MemRead(ex_MemRead),
        .out_MemWrite(ex_MemWrite), .out_MemToReg(ex_MemToReg),
        .out_ALUSrc(ex_ALUSrc), .out_Branch(ex_Branch),
        .out_Jump(ex_Jump), .out_ALUOp(ex_ALUOp),
        .out_csr_op(ex_csr_op), .out_csr_sel(ex_csr_sel),
        .out_pc(ex_pc), .out_read_data1(ex_read_data1),
        .out_read_data2(ex_read_data2), .out_imm(ex_imm),
        .out_rs1(ex_rs1), .out_rs2(ex_rs2), .out_rd(ex_rd),
        .out_funct3(ex_funct3), .out_funct7_5(ex_funct7_5), .out_funct7_0(ex_funct7_0),
        .out_opcode(ex_opcode), .out_csr_addr(ex_csr_addr)
    );

// ===========================================================
// HAZARD DETECTION UNIT
// ===========================================================
    wire        dcache_stall;
    hazard_unit u_hazard (
        .id_opcode   (id_opcode),
        .id_funct3   (id_funct3),
        .id_rs1      (id_rs1),
        .id_rs2      (id_rs2),
        .id_Branch   (id_Branch),
        .ex_RegWrite (ex_RegWrite),
        .ex_MemRead  (ex_MemRead),
        .ex_rd       (ex_rd),
        .mem_RegWrite(mem_RegWrite),
        .mem_MemRead (mem_MemRead),
        .mem_rd      (mem_rd),
        .id_redirect (id_mispredict),
        .trap_en     (id_trap_en),
        .icache_stall(icache_stall),
        .dcache_stall(dcache_stall),
        .stall_pc    (stall_pc),
        .stall_if_id (stall_if_id),
        .stall_id_ex (stall_id_ex),
        .stall_ex_mem(stall_ex_mem),
        .stall_mem_wb(stall_mem_wb),
        .flush_if_id (flush_if_id),
        .flush_id_ex (flush_id_ex),
        .flush_ex_mem(flush_ex_mem),
        .flush_mem_wb(flush_mem_wb)
    );

// ===========================================================
// FORWARDING UNIT
// ===========================================================
    wire [1:0] ForwardA, ForwardB;

    forwarding_unit u_fwd (
        .ex_rs1      (ex_rs1),
        .ex_rs2      (ex_rs2),
        .mem_rd      (mem_rd),
        .mem_RegWrite(mem_RegWrite),
        .wb_rd       (wb_rd),
        .wb_RegWrite (wb_RegWrite),
        .ForwardA    (ForwardA),
        .ForwardB    (ForwardB)
    );

// ===========================================================
// EX STAGE
// ===========================================================
    wire [3:0]  ex_ALUCtrl;
    wire        ex_is_mul_div;
    wire        ex_is_mul;

    alu_control u_aluctl (
        .ALUOp(ex_ALUOp), .funct3(ex_funct3),
        .funct7_5(ex_funct7_5), .funct7_0(ex_funct7_0), .opcode(ex_opcode),
        .ALUCtrl(ex_ALUCtrl), .is_mul_div(ex_is_mul_div), .is_mul(ex_is_mul)
    );

    // Operand A Forwarding Mux (uses mem_forward_data instead of mem_alu_result)
    wire [31:0] ex_fwd_a =
        (ForwardA == 2'b10) ? mem_forward_data :
        (ForwardA == 2'b01) ? wb_write_data    :
                              ex_read_data1;

    // Operand B Forwarding Mux (uses mem_forward_data instead of mem_alu_result)
    wire [31:0] ex_fwd_b =
        (ForwardB == 2'b10) ? mem_forward_data :
        (ForwardB == 2'b01) ? wb_write_data    :
                              ex_read_data2;

    // LUI/AUIPC operand A select logic
    wire ex_is_lui   = (ex_opcode == 7'b0110111);
    wire ex_is_auipc = (ex_opcode == 7'b0010111);
    wire [31:0] ex_alu_a = ex_is_auipc ? (ex_pc_plus4 - 4) : 
                           ex_is_lui   ? 32'b0 : 
                                         ex_fwd_a;

    wire [31:0] ex_alu_b = ex_ALUSrc ? ex_imm : ex_fwd_b;

    wire [31:0] alu_result_raw;
    wire        ex_zero;

    alu u_alu (
        .a(ex_alu_a), .b(ex_alu_b),
        .ALUCtrl(ex_ALUCtrl), .result(alu_result_raw), .zero(ex_zero)
    );

    // RV32M Multiplier/Divider
    wire [31:0] mul_div_result;
    mult_div u_mult_div (
        .a(ex_fwd_a), .b(ex_alu_b),
        .funct3(ex_funct3), .is_mul(ex_is_mul),
        .result(mul_div_result)
    );

    // CSR write-data generation in EX stage
    wire [31:0] csr_wdata_raw = ex_funct3[2] ? {27'b0, ex_rs1} : ex_fwd_a;

    // Output ALU result selector
    wire [31:0] ex_alu_result = ex_csr_sel   ? csr_wdata_raw :
                                ex_is_mul_div ? mul_div_result :
                                                alu_result_raw;

    wire [31:0] ex_branch_target = ex_pc + ex_imm;
    wire [31:0] ex_pc_plus4      = ex_pc + 32'd4;

// ===========================================================
// EX/MEM REGISTER
// ===========================================================
    wire        mem_MemRead, mem_MemWrite, mem_MemToReg;
    wire        mem_Branch, mem_zero, mem_Jump;
    wire [31:0] mem_branch_target, mem_write_data;
    wire [31:0] mem_pc_plus4;
    wire [2:0]  mem_funct3;
    wire [31:0] mem_read_data1_reg;
    wire [1:0]  mem_csr_op;
    wire        mem_csr_sel;
    wire [11:0] mem_csr_addr;

    ex_mem_reg u_ex_mem (
        .clk(clk), .rst(rst), .stall(stall_ex_mem), .flush(flush_ex_mem),
        .in_RegWrite(ex_RegWrite), .in_MemRead(ex_MemRead),
        .in_MemWrite(ex_MemWrite), .in_MemToReg(ex_MemToReg),
        .in_Branch(ex_Branch), .in_Jump(ex_Jump),
        .in_csr_op(ex_csr_op), .in_csr_sel(ex_csr_sel),
        .in_branch_target(ex_branch_target), .in_zero(ex_zero),
        .in_alu_result(ex_alu_result), .in_write_data(ex_fwd_b),
        .in_rd(ex_rd), .in_pc_plus4(ex_pc_plus4),
        .in_funct3(ex_funct3), .in_read_data1(ex_fwd_a), .in_csr_addr(ex_csr_addr),
        .out_RegWrite(mem_RegWrite), .out_MemRead(mem_MemRead),
        .out_MemWrite(mem_MemWrite), .out_MemToReg(mem_MemToReg),
        .out_Branch(mem_Branch), .out_Jump(jump_mem),
        .out_csr_op(mem_csr_op), .out_csr_sel(mem_csr_sel),
        .out_branch_target(branch_target_mem), .out_zero(mem_zero),
        .out_alu_result(mem_alu_result), .out_write_data(mem_write_data),
        .out_rd(mem_rd), .out_pc_plus4(mem_pc_plus4),
        .out_funct3(mem_funct3), .out_read_data1(mem_read_data1_reg),
        .out_csr_addr(mem_csr_addr)
    );

// ===========================================================
// MEM STAGE
// ===========================================================
    wire [31:0] mem_read_data;

    // MMIO System Decoder
    wire is_mmio = (mem_alu_result >= 32'h00002000);
    reg [31:0] cycle_counter;
    
    always @(posedge clk or posedge rst) begin
        if (rst) cycle_counter <= 32'b0;
        else     cycle_counter <= cycle_counter + 1;
    end
    
    wire [31:0] mmio_rdata = (mem_alu_result == 32'h00002008) ? cycle_counter : 32'b0;
    assign final_mem_read_data = is_mmio ? mmio_rdata : mem_read_data;

    // L1 Data Cache (gated with !is_mmio to bypass cache)
    wire        dmem_read, dmem_write;
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;

    cache_controller u_dcache (
        .clk      (clk),
        .rst      (rst),
        .cpu_read (mem_MemRead && !is_mmio),
        .cpu_write(mem_MemWrite && !is_mmio),
        .cpu_addr (mem_alu_result),
        .cpu_wdata(mem_write_data),
        .cpu_rdata(mem_read_data),
        .cpu_stall(dcache_stall),
        .mem_read (dmem_read),
        .mem_write(dmem_write),
        .mem_addr (dmem_addr),
        .mem_wdata(dmem_wdata),
        .mem_rdata(dmem_rdata)
    );

    data_mem u_dmem (
        .clk       (clk),
        .MemRead   (dmem_read),
        .MemWrite  (dmem_write),
        .addr      (dmem_addr),
        .write_data(dmem_wdata),
        .read_data (dmem_rdata)
    );

    // Simulation UART print
    always @(posedge clk) begin
        if (!rst && mem_MemWrite && (mem_alu_result == 32'h00002000) && !stall_ex_mem) begin
            $write("%c", mem_write_data[7:0]);
            $fflush(32'h80000001);
        end
    end

// ===========================================================
// MEM/WB REGISTER
// ===========================================================
    wire        wb_MemToReg, wb_Jump;
    wire [31:0] wb_read_data, wb_pc_plus4;
    wire [1:0]  wb_csr_op;
    wire        wb_csr_sel;
    wire [11:0] wb_csr_addr;

    mem_wb_reg u_mem_wb (
        .clk(clk), .rst(rst), .stall(stall_mem_wb), .flush(flush_mem_wb),
        .in_RegWrite(mem_RegWrite), .in_MemToReg(mem_MemToReg),
        .in_Jump(jump_mem), .in_csr_op(mem_csr_op), .in_csr_sel(mem_csr_sel),
        .in_read_data(final_mem_read_data), .in_alu_result(mem_alu_result),
        .in_rd(mem_rd), .in_pc_plus4(mem_pc_plus4), .in_csr_addr(mem_csr_addr),
        .out_RegWrite(wb_RegWrite), .out_MemToReg(wb_MemToReg),
        .out_Jump(wb_Jump), .out_csr_op(wb_csr_op), .out_csr_sel(wb_csr_sel),
        .out_read_data(wb_read_data), .out_alu_result(wb_alu_result),
        .out_rd(wb_rd), .out_pc_plus4(wb_pc_plus4), .out_csr_addr(wb_csr_addr)
    );

// ===========================================================
// WB STAGE
// ===========================================================
    wire [31:0] csr_rdata;

    csr_file u_csr (
        .clk         (clk),
        .rst         (rst),
        .csr_addr    (wb_csr_addr),
        .csr_wdata   (wb_alu_result), // holds the write operand calculated in EX stage
        .csr_op      (wb_csr_op),
        .csr_rdata   (csr_rdata),
        .inst_retired(wb_RegWrite && (wb_rd != 5'b0)),
        .trap_en     (id_trap_en),
        .trap_pc     (id_pc),
        .trap_cause  (id_trap_cause),
        .mtvec_out   (mtvec_out)
    );

    assign wb_write_data = wb_Jump     ? wb_pc_plus4  :
                           wb_csr_sel  ? csr_rdata    :
                           wb_MemToReg ? wb_read_data :
                                         wb_alu_result;

// ===========================================================
// DEBUG TAPS
// ===========================================================
    assign dbg_x1  = u_regfile.regs[1];
    assign dbg_x2  = u_regfile.regs[2];
    assign dbg_x3  = u_regfile.regs[3];
    assign dbg_x5  = u_regfile.regs[5];
    assign dbg_x6  = u_regfile.regs[6];
    assign dbg_x7  = u_regfile.regs[7];
    assign dbg_x8  = u_regfile.regs[8];
    assign dbg_x9  = u_regfile.regs[9];
    assign dbg_x10 = u_regfile.regs[10];
    assign dbg_x11 = u_regfile.regs[11];
    assign dbg_x12 = u_regfile.regs[12];
    assign dbg_x16 = u_regfile.regs[16];
    assign dbg_x17 = u_regfile.regs[17];

    assign dbg_dm0 = u_dmem.mem[0];
    assign dbg_dm1 = u_dmem.mem[1];
    assign dbg_dm2 = u_dmem.mem[2];

endmodule
