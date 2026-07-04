// ============================================================
// csr_file.v  –  Control and Status Registers (CSR)
// ============================================================
module csr_file (
    input  wire        clk,
    input  wire        rst,

    // CSR access interface (WB stage)
    input  wire [11:0] csr_addr,
    input  wire [31:0] csr_wdata,
    input  wire [1:0]  csr_op,          // 2'b00: read-only/none, 2'b01: write, 2'b10: set, 2'b11: clear
    output reg  [31:0] csr_rdata,

    // Counter interface
    input  wire        inst_retired,

    // Trap interface (ID stage)
    input  wire        trap_en,
    input  wire [31:0] trap_pc,
    input  wire [31:0] trap_cause,
    output wire [31:0] mtvec_out
);

    // CSR Registers
    reg [31:0] mstatus;
    reg [31:0] mtvec;
    reg [31:0] mepc;
    reg [31:0] mcause;
    reg [31:0] mcycle;
    reg [31:0] minstret;

    assign mtvec_out = mtvec;

    // Read CSR
    always @(*) begin
        case (csr_addr)
            12'h300: csr_rdata = mstatus;
            12'h305: csr_rdata = mtvec;
            12'h341: csr_rdata = mepc;
            12'h342: csr_rdata = mcause;
            12'hb00: csr_rdata = mcycle;      // mcycle
            12'hb02: csr_rdata = minstret;    // minstret
            default: csr_rdata = 32'b0;
        endcase
    end

    // Write/Update CSR
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mstatus  <= 32'h00001800; // M-mode default
            mtvec    <= 32'h00000040; // Default trap handler address
            mepc     <= 32'b0;
            mcause   <= 32'b0;
            mcycle   <= 32'b0;
            minstret <= 32'b0;
        end else begin
            // Increment counters
            mcycle <= mcycle + 32'd1;
            if (inst_retired)
                minstret <= minstret + 32'd1;

            // Handle traps (higher priority)
            if (trap_en) begin
                mepc   <= trap_pc;
                mcause <= trap_cause;
            end else if (csr_op != 2'b00) begin
                // Handle CSR instructions
                case (csr_addr)
                    12'h300: begin
                        if (csr_op == 2'b01) mstatus <= csr_wdata;
                        if (csr_op == 2'b10) mstatus <= mstatus | csr_wdata;
                        if (csr_op == 2'b11) mstatus <= mstatus & ~csr_wdata;
                    end
                    12'h305: begin
                        if (csr_op == 2'b01) mtvec <= csr_wdata;
                        if (csr_op == 2'b10) mtvec <= mtvec | csr_wdata;
                        if (csr_op == 2'b11) mtvec <= mtvec & ~csr_wdata;
                    end
                    12'h341: begin
                        if (csr_op == 2'b01) mepc <= csr_wdata;
                        if (csr_op == 2'b10) mepc <= mepc | csr_wdata;
                        if (csr_op == 2'b11) mepc <= mepc & ~csr_wdata;
                    end
                    12'h342: begin
                        if (csr_op == 2'b01) mcause <= csr_wdata;
                        if (csr_op == 2'b10) mcause <= mcause | csr_wdata;
                        if (csr_op == 2'b11) mcause <= mcause & ~csr_wdata;
                    end
                    // Counters can be written too
                    12'hb00: begin
                        if (csr_op == 2'b01) mcycle <= csr_wdata;
                    end
                    12'hb02: begin
                        if (csr_op == 2'b01) minstret <= csr_wdata;
                    end
                    default: ;
                endcase
            end
        end
    end

endmodule
