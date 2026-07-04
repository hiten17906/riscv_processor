// ============================================================
// hazard_unit.v  –  Hazard Detection Unit
//
// Responsibilities
// ─────────────────────────────────────────────────────────────
// 1. LOAD-USE STALL
//    Detected when the instruction in EX is a load (ex_MemRead=1)
//    and its destination register matches rs1 or rs2 of the
//    instruction currently in ID.
//    Action: stall PC + IF/ID for one cycle and insert a bubble
//            into ID/EX (flush_id_ex = 1).
//
// 2. BRANCH / JUMP FLUSH
//    Once a taken branch or jump is confirmed in the MEM stage
//    the two instructions fetched speculatively (in IF and ID)
//    must be discarded.
//    Action: flush IF/ID and ID/EX registers (flush_if_id = 1,
//            flush_id_ex = 1).  PC is already being redirected
//            by top.v via pc_next = branch_target_mem.
//
// Outputs
//   stall_pc      – hold PC (prevent increment)
//   stall_if_id   – hold IF/ID register (re-present same instr)
//   flush_if_id   – zero-out IF/ID  (insert NOP into ID stage)
//   flush_id_ex   – zero-out ID/EX  (insert bubble into EX stage)
// ============================================================
module hazard_unit (
    // From ID stage
    input  wire [6:0] id_opcode,
    input  wire [2:0] id_funct3,
    input  wire [4:0] id_rs1,
    input  wire [4:0] id_rs2,
    input  wire       id_Branch,

    // From EX stage
    input  wire       ex_RegWrite,
    input  wire       ex_MemRead,
    input  wire [4:0] ex_rd,

    // From MEM stage
    input  wire       mem_RegWrite,
    input  wire       mem_MemRead,
    input  wire [4:0] mem_rd,

    // Redirection and Trap inputs
    input  wire       id_redirect,
    input  wire       trap_en,

    // Cache stall inputs
    input  wire       icache_stall,
    input  wire       dcache_stall,

    // Stall outputs
    output wire       stall_pc,
    output wire       stall_if_id,
    output wire       stall_id_ex,
    output wire       stall_ex_mem,
    output wire       stall_mem_wb,

    // Flush outputs
    output wire       flush_if_id,
    output wire       flush_id_ex,
    output wire       flush_ex_mem,
    output wire       flush_mem_wb
);

    // ── ID instruction register usage decoding ───────────────────
    // SYSTEM opcode is 7'b1110011. CSR-immediate instructions have funct3[2] == 1'b1.
    wire id_is_csr_imm = (id_opcode == 7'b1110011) && (id_funct3[2] == 1'b1);

    wire id_reads_rs1 = (id_opcode != 7'b0110111) && // LUI
                        (id_opcode != 7'b0010111) && // AUIPC
                        (id_opcode != 7'b1101111) && // JAL
                        !id_is_csr_imm;

    wire id_reads_rs2 = (id_opcode == 7'b0110011) || 
                        (id_opcode == 7'b0100011) || 
                        (id_opcode == 7'b1100011);

    // ── Load-use stall (for normal instructions in ID) ───────────
    wire load_use_stall = ex_MemRead && (ex_rd != 5'b0) &&
                          ((id_reads_rs1 && (ex_rd == id_rs1)) || 
                           (id_reads_rs2 && (ex_rd == id_rs2)));

    // ── Branch/JALR stall (when operands are in EX, or loads in MEM) ──
    wire branch_jalr_in_id = id_Branch || (id_opcode == 7'b1100111);

    wire branch_stall = branch_jalr_in_id && (
        // 1. Preceding ALU/Load instruction in EX writes to rs1/rs2
        (ex_RegWrite && (ex_rd != 5'b0) &&
         ((id_reads_rs1 && (ex_rd == id_rs1)) || 
          (id_reads_rs2 && (ex_rd == id_rs2)))) ||
        // 2. Preceding Load instruction in MEM writes to rs1/rs2
        (mem_MemRead && (mem_rd != 5'b0) &&
         ((id_reads_rs1 && (mem_rd == id_rs1)) || 
          (id_reads_rs2 && (mem_rd == id_rs2))))
    );

    wire hazard_stall = load_use_stall || branch_stall;
    wire global_stall = icache_stall || dcache_stall;

    // ── Drive outputs ────────────────────────────────────────
    assign stall_pc     = global_stall || hazard_stall;
    assign stall_if_id  = global_stall || hazard_stall;
    assign stall_id_ex  = global_stall;
    assign stall_ex_mem = global_stall;
    assign stall_mem_wb = global_stall;

    assign flush_if_id  = !global_stall && (trap_en || (~hazard_stall && id_redirect));
    assign flush_id_ex  = !global_stall && (trap_en || hazard_stall);
    assign flush_ex_mem = !global_stall && trap_en;
    assign flush_mem_wb = !global_stall && trap_en;

endmodule
