// ============================================================
// ex_mem_reg.v  –  EX/MEM Pipeline Register with Stall + Flush + CSR
// ============================================================
module ex_mem_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        stall,
    input  wire        flush,

    // Control signals in
    input  wire        in_RegWrite,
    input  wire        in_MemRead,
    input  wire        in_MemWrite,
    input  wire        in_MemToReg,
    input  wire        in_Branch,
    input  wire        in_Jump,
    input  wire [1:0]  in_csr_op,
    input  wire        in_csr_sel,

    // Data in
    input  wire [31:0] in_branch_target,
    input  wire        in_zero,
    input  wire [31:0] in_alu_result,
    input  wire [31:0] in_write_data,
    input  wire [4:0]  in_rd,
    input  wire [31:0] in_pc_plus4,
    input  wire [2:0]  in_funct3,
    input  wire [31:0] in_read_data1,
    input  wire [11:0] in_csr_addr,

    // Control signals out
    output reg         out_RegWrite,
    output reg         out_MemRead,
    output reg         out_MemWrite,
    output reg         out_MemToReg,
    output reg         out_Branch,
    output reg         out_Jump,
    output reg  [1:0]  out_csr_op,
    output reg         out_csr_sel,

    // Data out
    output reg  [31:0] out_branch_target,
    output reg         out_zero,
    output reg  [31:0] out_alu_result,
    output reg  [31:0] out_write_data,
    output reg  [4:0]  out_rd,
    output reg  [31:0] out_pc_plus4,
    output reg  [2:0]  out_funct3,
    output reg  [31:0] out_read_data1,
    output reg  [11:0] out_csr_addr
);
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            out_RegWrite      <= 1'b0;
            out_MemRead       <= 1'b0;
            out_MemWrite      <= 1'b0;
            out_MemToReg      <= 1'b0;
            out_Branch        <= 1'b0;
            out_Jump          <= 1'b0;
            out_csr_op        <= 2'b0;
            out_csr_sel       <= 1'b0;
            out_branch_target <= 32'b0;
            out_zero          <= 1'b0;
            out_alu_result    <= 32'b0;
            out_write_data    <= 32'b0;
            out_rd            <= 5'b0;
            out_pc_plus4      <= 32'b0;
            out_funct3        <= 3'b0;
            out_read_data1    <= 32'b0;
            out_csr_addr      <= 12'b0;
        end else if (flush) begin
            out_RegWrite      <= 1'b0;
            out_MemRead       <= 1'b0;
            out_MemWrite      <= 1'b0;
            out_MemToReg      <= 1'b0;
            out_Branch        <= 1'b0;
            out_Jump          <= 1'b0;
            out_csr_op        <= 2'b0;
            out_csr_sel       <= 1'b0;
            out_branch_target <= 32'b0;
            out_zero          <= 1'b0;
            out_alu_result    <= 32'b0;
            out_write_data    <= 32'b0;
            out_rd            <= 5'b0;
            out_pc_plus4      <= 32'b0;
            out_funct3        <= 3'b0;
            out_read_data1    <= 32'b0;
            out_csr_addr      <= 12'b0;
        end else if (!stall) begin
            out_RegWrite      <= in_RegWrite;
            out_MemRead       <= in_MemRead;
            out_MemWrite      <= in_MemWrite;
            out_MemToReg      <= in_MemToReg;
            out_Branch        <= in_Branch;
            out_Jump          <= in_Jump;
            out_csr_op        <= in_csr_op;
            out_csr_sel       <= in_csr_sel;
            out_branch_target <= in_branch_target;
            out_zero          <= in_zero;
            out_alu_result    <= in_alu_result;
            out_write_data    <= in_write_data;
            out_rd            <= in_rd;
            out_pc_plus4      <= in_pc_plus4;
            out_funct3        <= in_funct3;
            out_read_data1    <= in_read_data1;
            out_csr_addr      <= in_csr_addr;
        end
    end
endmodule
