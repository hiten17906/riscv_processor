// ============================================================
// alu_control.v  –  ALU Control
//
// ALUOp | meaning
// ------+---------
//  00   | ADD  (lw / sw address calculation)
//  01   | SUB  (branch comparison — use SUB, check zero/sign)
//  10   | look at funct3 / funct7 (R-type and I-type arithmetic)
//
// ALUCtrl encoding (sent to ALU):
//  0000  ADD
//  0001  SUB
//  0010  AND
//  0011  OR
//  0100  SLT  (signed less-than)
//  0101  SLTU (unsigned less-than)
//  0110  XOR
//  0111  SLL
//  1000  SRL
//  1001  SRA
// ============================================================
module alu_control (
    input  wire [1:0] ALUOp,
    input  wire [2:0] funct3,
    input  wire       funct7_5,   // instruction bit 30
    input  wire       funct7_0,   // instruction bit 25
    input  wire [6:0] opcode,
    output reg  [3:0] ALUCtrl,
    output reg        is_mul_div, // 1 if RV32M instruction
    output reg        is_mul      // 1 if multiplication, 0 if division
);
    localparam I_ARITH = 7'b0010011;

    always @(*) begin
        ALUCtrl    = 4'b0000;
        is_mul_div = 1'b0;
        is_mul     = 1'b0;

        case (ALUOp)
            2'b00: ALUCtrl = 4'b0000; // ADD (load/store)

            2'b01: ALUCtrl = 4'b0001; // SUB (branch)

            2'b10: begin
                if (funct7_0 && (opcode == 7'b0110011)) begin
                    // RV32M multiplication/division
                    is_mul_div = 1'b1;
                    is_mul     = ~funct3[2];
                end else begin
                    case (funct3)
                        3'b000: // ADD / SUB / ADDI
                            ALUCtrl = (funct7_5 && (opcode != I_ARITH))
                                      ? 4'b0001   // SUB
                                      : 4'b0000;  // ADD / ADDI
                        3'b111: ALUCtrl = 4'b0010; // AND / ANDI
                        3'b110: ALUCtrl = 4'b0011; // OR  / ORI
                        3'b010: ALUCtrl = 4'b0100; // SLT / SLTI
                        3'b011: ALUCtrl = 4'b0101; // SLTU/ SLTIU
                        3'b100: ALUCtrl = 4'b0110; // XOR / XORI
                        3'b001: ALUCtrl = 4'b0111; // SLL / SLLI
                        3'b101: ALUCtrl = funct7_5 ? 4'b1001 : 4'b1000; // SRA : SRL
                        default: ALUCtrl = 4'b0000;
                    endcase
                end
            end

            default: ALUCtrl = 4'b0000;
        endcase
    end
endmodule
