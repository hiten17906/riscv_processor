// ============================================================
// mult_div.v  –  RV32M Combinational Multiplier and Divider
// ============================================================
module mult_div (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [2:0]  funct3,
    input  wire        is_mul,
    output reg  [31:0] result
);

    // Multiplication results
    wire signed [63:0] mul_signed     = $signed(a) * $signed(b);
    wire [63:0]        mul_unsigned   = a * b;
    wire signed [63:0] mul_signed_unsigned = $signed(a) * $signed({1'b0, b});

    always @(*) begin
        if (is_mul) begin
            case (funct3)
                3'b000: result = mul_signed[31:0];                        // mul
                3'b001: result = mul_signed[63:32];                       // mulh
                3'b010: result = mul_signed_unsigned[63:32];              // mulhsu
                3'b011: result = mul_unsigned[63:32];                     // mulhu
                default: result = 32'b0;
            endcase
        end else begin
            // Division & Remainder (with RISC-V edge cases)
            if (b == 32'b0) begin
                case (funct3)
                    3'b100, 3'b101: result = 32'hffffffff;               // div / divu
                    3'b110, 3'b111: result = a;                          // rem / remu
                    default: result = 32'b0;
                endcase
            end else if (a == 32'h80000000 && b == 32'hffffffff && funct3[1:0] == 2'b00) begin
                // Signed overflow: 80000000 / -1
                if (funct3 == 3'b100)
                    result = 32'h80000000;                               // div
                else
                    result = 32'b0;                                      // rem
            end else begin
                case (funct3)
                    3'b100: result = $signed(a) / $signed(b);             // div
                    3'b101: result = a / b;                              // divu
                    3'b110: result = $signed(a) % $signed(b);             // rem
                    3'b111: result = a % b;                              // remu
                    default: result = 32'b0;
                endcase
            end
        end
    end

endmodule
