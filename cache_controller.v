// ============================================================
// cache_controller.v  –  Direct-Mapped L1 Cache Controller
// ============================================================
module cache_controller (
    input  wire        clk,
    input  wire        rst,

    // CPU interface
    input  wire        cpu_read,
    input  wire        cpu_write,
    input  wire [31:0] cpu_addr,
    input  wire [31:0] cpu_wdata,
    output reg  [31:0] cpu_rdata,
    output wire        cpu_stall,

    // Main Memory interface
    output wire        mem_read,
    output wire        mem_write,
    output wire [31:0] mem_addr,
    output wire [31:0] mem_wdata,
    input  wire [31:0] mem_rdata
);

    // 8-entry direct-mapped cache (each block = 1 word = 4 bytes)
    reg [31:0] cache_data  [0:7];
    reg [26:0] cache_tag   [0:7];
    reg        cache_valid [0:7];

    wire [2:0]  index = cpu_addr[4:2];
    wire [26:0] tag   = cpu_addr[31:5];

    // Cache hit logic
    wire hit = cache_valid[index] && (cache_tag[index] == tag);

    // Main memory interface assignments
    assign mem_addr  = cpu_addr;
    assign mem_wdata = cpu_wdata;

    // FSM States
    localparam IDLE  = 3'd0;
    localparam WAIT0 = 3'd1;
    localparam WAIT1 = 3'd2;
    localparam WAIT2 = 3'd3;
    localparam WAIT3 = 3'd4;
    localparam FILL  = 3'd5;

    reg [2:0] state;

    // Combinational control outputs
    assign cpu_stall = (state == IDLE) ? (cpu_read && !hit) : (state != FILL);
    assign mem_read  = (state == IDLE) ? (cpu_read && !hit) : (state != FILL);
    assign mem_write = (state == IDLE) ? cpu_write : 1'b0;

    integer i;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= IDLE;
            for (i = 0; i < 8; i = i + 1) begin
                cache_data[i]  <= 32'b0;
                cache_tag[i]   <= 27'b0;
                cache_valid[i] <= 1'b0;
            end
        end else begin
            case (state)
                IDLE: begin
                    if (cpu_write) begin
                        // Write-through: write to cache and write to memory immediately.
                        // Both cache and main memory write operations commit synchronously at the next clock edge,
                        // keeping both memories in 100% consistent state without requiring write latency stalls.
                        cache_data[index]  <= cpu_wdata;
                        cache_tag[index]   <= tag;
                        cache_valid[index] <= 1'b1;
                        state              <= IDLE;
                    end else if (cpu_read && !hit) begin
                        // Miss: start 4-cycle memory latency wait
                        state     <= WAIT0;
                    end
                end

                WAIT0: state <= WAIT1;
                WAIT1: state <= WAIT2;
                WAIT2: state <= WAIT3;
                WAIT3: state <= FILL;

                FILL: begin
                    // Latch data from main memory into cache
                    cache_data[index]  <= mem_rdata;
                    cache_tag[index]   <= tag;
                    cache_valid[index] <= 1'b1;
                    state              <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    // Combinational CPU read data selection
    always @(*) begin
        if (cpu_read && hit) begin
            cpu_rdata = cache_data[index];
        end else if (state == FILL) begin
            cpu_rdata = mem_rdata; // Bypass straight to CPU when fill is ready
        end else begin
            cpu_rdata = 32'b0;
        end
    end

endmodule
