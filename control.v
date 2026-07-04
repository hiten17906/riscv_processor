// ============================================================
// control.v  –  Main Control Unit
// Decodes the 7-bit opcode and generates pipeline control signals.
//
// RegWrite  – write result back to register file
// MemRead   – read from data memory (lw)
// MemWrite  – write to data memory  (sw)
// MemToReg  – 1 → write memory data to rd; 0 → write ALU result
// ALUSrc    – 1 → second ALU operand is immediate; 0 → rs2
// Branch    – instruction is a branch (beq / bne / blt / bge)
// Jump      – instruction is jal / jalr
// ALUOp[1:0]– 00 lw/sw  01 branch  10 R-type/I-type arithmetic
// ============================================================
module control (
    input  wire [6:0]  opcode,
    input  wire [2:0]  funct3,
    input  wire [11:0] funct12, // instr[31:20]
    output reg         RegWrite,
    output reg         MemRead,
    output reg         MemWrite,
    output reg         MemToReg,
    output reg         ALUSrc,
    output reg         Branch,
    output reg         Jump,
    output reg  [1:0]  ALUOp,

    // CSR and Trap outputs
    output reg  [1:0]  csr_op,
    output reg         csr_sel,
    output reg         trap_en,
    output reg  [31:0] trap_cause
);
    // RISC-V opcodes
    localparam R_TYPE  = 7'b0110011; // add, sub, and, or, slt, mul, div
    localparam I_ARITH = 7'b0010011; // addi, andi, ori, slti
    localparam LOAD    = 7'b0000011; // lw
    localparam STORE   = 7'b0100011; // sw
    localparam BRANCH  = 7'b1100011; // beq, bne, blt, bge
    localparam JAL     = 7'b1101111;
    localparam JALR    = 7'b1100111;
    localparam SYSTEM  = 7'b1110011; // CSR, ecall, ebreak
    localparam LUI     = 7'b0110111;
    localparam AUIPC   = 7'b0010111;

    always @(*) begin
        // safe defaults
        RegWrite   = 1'b0;
        MemRead    = 1'b0;
        MemWrite   = 1'b0;
        MemToReg   = 1'b0;
        ALUSrc     = 1'b0;
        Branch     = 1'b0;
        Jump       = 1'b0;
        ALUOp      = 2'b00;
        csr_op     = 2'b00;
        csr_sel    = 1'b0;
        trap_en    = 1'b0;
        trap_cause = 32'b0;

        case (opcode)
            R_TYPE: begin
                RegWrite = 1'b1;
                ALUOp    = 2'b10;
            end
            I_ARITH: begin
                RegWrite = 1'b1;
                ALUSrc   = 1'b1;
                ALUOp    = 2'b10;
            end
            LOAD: begin
                RegWrite = 1'b1;
                MemRead  = 1'b1;
                MemToReg = 1'b1;
                ALUSrc   = 1'b1;
                ALUOp    = 2'b00;
            end
            STORE: begin
                MemWrite = 1'b1;
                ALUSrc   = 1'b1;
                ALUOp    = 2'b00;
            end
            BRANCH: begin
                Branch   = 1'b1;
                ALUOp    = 2'b01;
            end
            JAL: begin
                RegWrite = 1'b1;
                Jump     = 1'b1;
                ALUSrc   = 1'b1;
                ALUOp    = 2'b00;
            end
            JALR: begin
                RegWrite = 1'b1;
                Jump     = 1'b1;
                ALUSrc   = 1'b1;
                ALUOp    = 2'b00;
            end
            SYSTEM: begin
                if (funct3 == 3'b000) begin
                    // ecall or ebreak
                    trap_en = 1'b1;
                    if (funct12 == 12'b000000000000)
                        trap_cause = 32'd11; // ecall from M-mode
                    else if (funct12 == 12'b000000000001)
                        trap_cause = 32'd3;  // ebreak
                end else begin
                    // CSR instructions
                    RegWrite = 1'b1;
                    csr_sel  = 1'b1;
                    csr_op   = funct3[1:0];
                end
            end
            LUI: begin
                RegWrite = 1'b1;
                ALUSrc   = 1'b1;
                ALUOp    = 2'b00;
            end
            AUIPC: begin
                RegWrite = 1'b1;
                ALUSrc   = 1'b1;
                ALUOp    = 2'b00;
            end
            default: begin
                // NOP / unknown
            end
        endcase
    end
endmodule
