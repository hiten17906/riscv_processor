// ============================================================
// data_mem.v  –  Data Memory (64 words = 256 bytes)
// Synchronous write, synchronous read.
// ============================================================
module data_mem (
    input  wire        clk,
    input  wire        MemRead,
    input  wire        MemWrite,
    input  wire [31:0] addr,
    input  wire [31:0] write_data,
    output reg  [31:0] read_data
);
    reg [31:0] mem [0:63];

    integer i;
    initial begin
        for (i = 0; i < 64; i = i + 1)
            mem[i] = 32'b0;
    end

    // Synchronous write
    always @(posedge clk) begin
        if (MemWrite)
            mem[addr[7:2]] <= write_data;
    end

    // Synchronous read
    always @(posedge clk) begin
        if (MemRead)
            read_data <= mem[addr[7:2]];
        else
            read_data <= 32'b0;
    end
endmodule
