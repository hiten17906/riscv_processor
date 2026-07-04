module instr_mem (
    input  wire        clk,
    input  wire [31:0] addr,
    output reg  [31:0] instr
);
    reg [31:0] mem [0:63];

    initial begin
        $readmemh("instructions.hex", mem);
    end

    // Synchronous read
    always @(posedge clk) begin
        instr <= mem[addr[7:2]];
    end
endmodule
