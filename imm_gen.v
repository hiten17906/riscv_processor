// ============================================================
// imm_gen.v  –  Immediate Generator
// Produces a sign-extended 32-bit immediate from the instruction.
//
// Supported formats:
//   I-type  (LOAD, I-arith, JALR)
//   S-type  (STORE)
//   B-type  (BRANCH)
//   J-type  (JAL)
//   U-type  (LUI, AUIPC – not required but included for completeness)
// ============================================================
module imm_gen (
    input  wire [31:0] instr,
    output reg  [31:0] imm_out
);
    wire [6:0] opcode = instr[6:0];

    localparam I_ARITH = 7'b0010011;
    localparam LOAD    = 7'b0000011;
    localparam JALR    = 7'b1100111;
    localparam STORE   = 7'b0100011;
    localparam BRANCH  = 7'b1100011;
    localparam JAL     = 7'b1101111;
    localparam LUI     = 7'b0110111;
    localparam AUIPC   = 7'b0010111;

    always @(*) begin
        case (opcode)
            // I-type: bits [31:20]
            I_ARITH, LOAD, JALR:
                imm_out = {{20{instr[31]}}, instr[31:20]};

            // S-type: {instr[31:25], instr[11:7]}
            STORE:
                imm_out = {{20{instr[31]}}, instr[31:25], instr[11:7]};

            // B-type: {instr[31], instr[7], instr[30:25], instr[11:8], 1'b0}
            BRANCH:
                imm_out = {{19{instr[31]}}, instr[31], instr[7],
                           instr[30:25], instr[11:8], 1'b0};

            // J-type: {instr[31], instr[19:12], instr[20], instr[30:21], 1'b0}
            JAL:
                imm_out = {{11{instr[31]}}, instr[31], instr[19:12],
                           instr[20], instr[30:21], 1'b0};

            // U-type
            LUI, AUIPC:
                imm_out = {instr[31:12], 12'b0};

            default:
                imm_out = 32'b0;
        endcase
    end
endmodule
