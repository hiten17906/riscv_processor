// ============================================================
// forwarding_unit.v  –  Data-Forwarding Unit
//
// Generates 2-bit mux-select signals for the two ALU operand
// inputs in the EX stage so that results computed in MEM or WB
// can bypass the register file.
//
// ForwardA / ForwardB encoding
// ────────────────────────────
//  2'b00  →  use register-file value from ID/EX  (no hazard)
//  2'b10  →  forward ALU result from EX/MEM      (MEM-stage forward)
//  2'b01  →  forward write-back value from MEM/WB (WB-stage forward)
//
// Priority: MEM-stage forward takes priority over WB-stage
// forward for the same register (the MEM value is newer).
//
// Forwarding is suppressed for x0 (writes to x0 are meaningless).
// ============================================================
module forwarding_unit (
    // EX-stage source registers (from ID/EX register)
    input  wire [4:0] ex_rs1,
    input  wire [4:0] ex_rs2,

    // MEM-stage destination (from EX/MEM register)
    input  wire [4:0] mem_rd,
    input  wire       mem_RegWrite,

    // WB-stage destination (from MEM/WB register)
    input  wire [4:0] wb_rd,
    input  wire       wb_RegWrite,

    // Forwarding selects
    output reg  [1:0] ForwardA,    // mux select for ALU operand A
    output reg  [1:0] ForwardB     // mux select for ALU operand B
);

    always @(*) begin
        // ── ForwardA (rs1) ───────────────────────────────────
        if (mem_RegWrite && (mem_rd != 5'b0) && (mem_rd == ex_rs1))
            ForwardA = 2'b10;   // forward from MEM stage
        else if (wb_RegWrite && (wb_rd != 5'b0) && (wb_rd == ex_rs1))
            ForwardA = 2'b01;   // forward from WB stage
        else
            ForwardA = 2'b00;   // no forwarding

        // ── ForwardB (rs2) ───────────────────────────────────
        if (mem_RegWrite && (mem_rd != 5'b0) && (mem_rd == ex_rs2))
            ForwardB = 2'b10;   // forward from MEM stage
        else if (wb_RegWrite && (wb_rd != 5'b0) && (wb_rd == ex_rs2))
            ForwardB = 2'b01;   // forward from WB stage
        else
            ForwardB = 2'b00;   // no forwarding
    end

endmodule
