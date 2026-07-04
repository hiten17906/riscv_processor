// ============================================================
// reg_file.v  –  32 × 32-bit Register File
// x0 is hardwired to 0.
// Write on posedge clk, read asynchronously (combinational).
// ============================================================
module reg_file (
    input  wire        clk,
    input  wire        rst,
    input  wire        RegWrite,
    input  wire [4:0]  rs1,
    input  wire [4:0]  rs2,
    input  wire [4:0]  rd,
    input  wire [31:0] write_data,
    output wire [31:0] read_data1,
    output wire [31:0] read_data2
);
    reg [31:0] regs [0:31];

    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1)
            regs[i] = 32'b0;
    end

    // Synchronous write (x0 stays 0) with asynchronous reset
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'b0;
        end else if (RegWrite && rd != 5'b0) begin
            regs[rd] <= write_data;
        end
    end

    // Asynchronous read with write-first (write-through) behavior
    assign read_data1 = (rs1 == 5'b0) ? 32'b0 :
                        (RegWrite && (rs1 == rd)) ? write_data :
                                                    regs[rs1];
    assign read_data2 = (rs2 == 5'b0) ? 32'b0 :
                        (RegWrite && (rs2 == rd)) ? write_data :
                                                    regs[rs2];
endmodule
