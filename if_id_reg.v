// ============================================================
// if_id_reg.v  –  IF/ID Pipeline Register
// ============================================================
module if_id_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] if_pc,
    input  wire [31:0] if_instr,
    output reg  [31:0] id_pc,
    output reg  [31:0] id_instr
);
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            id_pc    <= 32'b0;
            id_instr <= 32'b0;
        end else begin
            id_pc    <= if_pc;
            id_instr <= if_instr;
        end
    end
endmodule
