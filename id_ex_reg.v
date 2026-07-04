// ============================================================
// id_ex_reg.v  –  ID/EX Pipeline Register with Stall + Flush + CSR
// ============================================================
module id_ex_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,
    input  wire        flush,

    // Control signals in
    input  wire        in_RegWrite,
    input  wire        in_MemRead,
    input  wire        in_MemWrite,
    input  wire        in_MemToReg,
    input  wire        in_ALUSrc,
    input  wire        in_Branch,
    input  wire        in_Jump,
    input  wire [1:0]  in_ALUOp,
    input  wire [1:0]  in_csr_op,
    input  wire        in_csr_sel,

    // Data in
    input  wire [31:0] in_pc,
    input  wire [31:0] in_read_data1,
    input  wire [31:0] in_read_data2,
    input  wire [31:0] in_imm,
    input  wire [4:0]  in_rs1,
    input  wire [4:0]  in_rs2,
    input  wire [4:0]  in_rd,
    input  wire [2:0]  in_funct3,
    input  wire        in_funct7_5,
    input  wire        in_funct7_0,
    input  wire [6:0]  in_opcode,
    input  wire [11:0] in_csr_addr,

    // Control signals out
    output reg         out_RegWrite,
    output reg         out_MemRead,
    output reg         out_MemWrite,
    output reg         out_MemToReg,
    output reg         out_ALUSrc,
    output reg         out_Branch,
    output reg         out_Jump,
    output reg  [1:0]  out_ALUOp,
    output reg  [1:0]  out_csr_op,
    output reg         out_csr_sel,

    // Data out
    output reg  [31:0] out_pc,
    output reg  [31:0] out_read_data1,
    output reg  [31:0] out_read_data2,
    output reg  [31:0] out_imm,
    output reg  [4:0]  out_rs1,
    output reg  [4:0]  out_rs2,
    output reg  [4:0]  out_rd,
    output reg  [2:0]  out_funct3,
    output reg         out_funct7_5,
    output reg         out_funct7_0,
    output reg  [6:0]  out_opcode,
    output reg  [11:0] out_csr_addr
);
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            out_RegWrite    <= 1'b0;
            out_MemRead     <= 1'b0;
            out_MemWrite    <= 1'b0;
            out_MemToReg    <= 1'b0;
            out_ALUSrc      <= 1'b0;
            out_Branch      <= 1'b0;
            out_Jump        <= 1'b0;
            out_ALUOp       <= 2'b0;
            out_csr_op      <= 2'b0;
            out_csr_sel     <= 1'b0;
            out_pc          <= 32'b0;
            out_read_data1  <= 32'b0;
            out_read_data2  <= 32'b0;
            out_imm         <= 32'b0;
            out_rs1         <= 5'b0;
            out_rs2         <= 5'b0;
            out_rd          <= 5'b0;
            out_funct3      <= 3'b0;
            out_funct7_5    <= 1'b0;
            out_funct7_0    <= 1'b0;
            out_opcode      <= 7'b0;
            out_csr_addr    <= 12'b0;
        end else if (flush) begin
            out_RegWrite    <= 1'b0;
            out_MemRead     <= 1'b0;
            out_MemWrite    <= 1'b0;
            out_MemToReg    <= 1'b0;
            out_ALUSrc      <= 1'b0;
            out_Branch      <= 1'b0;
            out_Jump        <= 1'b0;
            out_ALUOp       <= 2'b0;
            out_csr_op      <= 2'b0;
            out_csr_sel     <= 1'b0;
            out_pc          <= 32'b0;
            out_read_data1  <= 32'b0;
            out_read_data2  <= 32'b0;
            out_imm         <= 32'b0;
            out_rs1         <= 5'b0;
            out_rs2         <= 5'b0;
            out_rd          <= 5'b0;
            out_funct3      <= 3'b0;
            out_funct7_5    <= 1'b0;
            out_funct7_0    <= 1'b0;
            out_opcode      <= 7'b0;
            out_csr_addr    <= 12'b0;
        end else if (!stall) begin
            out_RegWrite    <= in_RegWrite;
            out_MemRead     <= in_MemRead;
            out_MemWrite    <= in_MemWrite;
            out_MemToReg    <= in_MemToReg;
            out_ALUSrc      <= in_ALUSrc;
            out_Branch      <= in_Branch;
            out_Jump        <= in_Jump;
            out_ALUOp       <= in_ALUOp;
            out_csr_op      <= in_csr_op;
            out_csr_sel     <= in_csr_sel;
            out_pc          <= in_pc;
            out_read_data1  <= in_read_data1;
            out_read_data2  <= in_read_data2;
            out_imm         <= in_imm;
            out_rs1         <= in_rs1;
            out_rs2         <= in_rs2;
            out_rd          <= in_rd;
            out_funct3      <= in_funct3;
            out_funct7_5    <= in_funct7_5;
            out_funct7_0    <= in_funct7_0;
            out_opcode      <= in_opcode;
            out_csr_addr    <= in_csr_addr;
        end
    end
endmodule
