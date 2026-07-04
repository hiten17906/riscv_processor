#include <iostream>
#include <fstream>
#include <vector>
#include <string>
#include <iomanip>
#include <cstdint>
#include <sstream>

// CPU Architectural State
uint32_t pc = 0;
uint32_t regs[32] = {0};
uint32_t dmem[64] = {0};

// CSR Registers
uint32_t mtvec = 64; // default
uint32_t mepc = 0;
uint32_t mcause = 0;

// Program memory (64 words = 256 bytes)
uint32_t imem[64] = {0x00000013}; // Initialised to NOPs

// Helper to convert string hex to uint32
uint32_t parse_hex(const std::string& s) {
    uint32_t val;
    std::stringstream ss;
    ss << std::hex << s;
    ss >> val;
    return val;
}

int main() {
    // 1. Load program from program.hex
    std::ifstream hex_file("program.hex");
    if (!hex_file.is_open()) {
        std::cerr << "Error: Could not open program.hex" << std::endl;
        return 1;
    }

    std::string line;
    int idx = 0;
    while (std::getline(hex_file, line) && idx < 64) {
        if (!line.empty() && line[0] != '/' && line[0] != '#') {
            imem[idx++] = parse_hex(line);
        }
    }
    hex_file.close();

    // 2. Open golden trace file
    std::ofstream trace_file("golden_trace.log");
    if (!trace_file.is_open()) {
        std::cerr << "Error: Could not create golden_trace.log" << std::endl;
        return 1;
    }

    // 3. Execution loop
    bool running = true;
    int cycle_limit = 500;
    int cycles = 0;

    while (running && cycles < cycle_limit) {
        cycles++;
        uint32_t current_pc = pc;
        uint32_t instr = imem[(pc & 0xff) >> 2]; // wrap around mask to match ROM

        // Check for halt self-loop: JAL x0, 0 -> 0x0000006f
        if (instr == 0x0000006f) {
            trace_file << "HALT" << std::endl;
            break;
        }

        // Decode fields
        uint32_t opcode = instr & 0x7f;
        uint32_t rd     = (instr >> 7) & 0x1f;
        uint32_t funct3 = (instr >> 12) & 0x07;
        uint32_t rs1    = (instr >> 15) & 0x1f;
        uint32_t rs2    = (instr >> 20) & 0x1f;
        uint32_t funct7 = (instr >> 25) & 0x7f;

        // Immediates
        int32_t imm_i = (int32_t)instr >> 20;
        int32_t imm_s = (((int32_t)instr >> 25) << 5) | (int32_t)((instr >> 7) & 0x1f);
        if (imm_s & 0x800) imm_s |= 0xfffff000; // sign extension
        
        int32_t imm_b = (((instr >> 31) & 1) << 12) |
                        (((instr >> 7) & 1) << 11) |
                        (((instr >> 25) & 0x3f) << 5) |
                        (((instr >> 8) & 0x0f) << 1);
        if (imm_b & 0x1000) imm_b |= 0xffffe000; // sign extension

        int32_t imm_j = (((instr >> 31) & 1) << 20) |
                        (instr & 0x000ff000) |
                        (((instr >> 20) & 1) << 11) |
                        (((instr >> 21) & 0x3ff) << 1);
        if (imm_j & 0x100000) imm_j |= 0xffe00000; // sign extension

        // Read register values
        uint32_t val1 = regs[rs1];
        uint32_t val2 = regs[rs2];

        // Trace logging variables
        bool reg_write = false;
        uint32_t write_val = 0;
        bool mem_write = false;
        uint32_t mem_addr = 0;
        uint32_t mem_val = 0;

        uint32_t next_pc = pc + 4;

        if (opcode == 0x13) { // OP-IMM
            reg_write = true;
            if (funct3 == 0x0) { // ADDI
                write_val = val1 + imm_i;
            } else if (funct3 == 0x2) { // SLTI
                write_val = ((int32_t)val1 < imm_i) ? 1 : 0;
            } else if (funct3 == 0x6) { // ORI
                write_val = val1 | imm_i;
            } else if (funct3 == 0x7) { // ANDI
                write_val = val1 & imm_i;
            }
        } 
        else if (opcode == 0x33) { // OP (R-type)
            reg_write = true;
            if (funct7 == 0x01) { // RV32M Extensions
                if (funct3 == 0x0) { // MUL
                    write_val = (int32_t)val1 * (int32_t)val2;
                } else if (funct3 == 0x4) { // DIV
                    if (val2 == 0) write_val = -1;
                    else if ((int32_t)val1 == (int32_t)0x80000000 && (int32_t)val2 == -1) write_val = val1;
                    else write_val = (int32_t)val1 / (int32_t)val2;
                } else if (funct3 == 0x6) { // REM
                    if (val2 == 0) write_val = val1;
                    else if ((int32_t)val1 == (int32_t)0x80000000 && (int32_t)val2 == -1) write_val = 0;
                    else write_val = (int32_t)val1 % (int32_t)val2;
                }
            } else { // Standard R-type
                if (funct3 == 0x0) {
                    if (funct7 == 0x20) write_val = val1 - val2; // SUB
                    else write_val = val1 + val2; // ADD
                } else if (funct3 == 0x7) { // AND
                    write_val = val1 & val2;
                } else if (funct3 == 0x2) { // SLT
                    write_val = ((int32_t)val1 < (int32_t)val2) ? 1 : 0;
                } else if (funct3 == 0x6) { // OR
                    write_val = val1 | val2;
                }
            }
        } 
        else if (opcode == 0x23) { // STORE
            mem_write = true;
            mem_addr = val1 + imm_s;
            mem_val = val2;
            if (mem_addr == 0x00002000) {
                std::cout << (char)(mem_val & 0xff);
                std::cout.flush();
            } else {
                dmem[(mem_addr & 0xff) >> 2] = mem_val;
            }
        } 
        else if (opcode == 0x03) { // LOAD
            reg_write = true;
            uint32_t addr = val1 + imm_i;
            if (addr == 0x00002008) {
                write_val = cycles;
            } else {
                write_val = dmem[(addr & 0xff) >> 2];
            }
        } 
        else if (opcode == 0x63) { // BRANCH
            bool take = false;
            if (funct3 == 0x0) take = (val1 == val2); // BEQ
            else if (funct3 == 0x1) take = (val1 != val2); // BNE
            
            if (take) {
                next_pc = pc + imm_b;
            }
        } 
        else if (opcode == 0x6f) { // JAL
            reg_write = true;
            write_val = pc + 4;
            next_pc = pc + imm_j;
        } 
        else if (opcode == 0x67) { // JALR
            reg_write = true;
            write_val = pc + 4;
            next_pc = (val1 + imm_i) & 0xfffffffe;
        } 
        else if (opcode == 0x73) { // SYSTEM
            uint32_t csr_addr = imm_i & 0xfff;
            if (funct3 == 0x0) { // ecall/ebreak
                // Trap Handling
                mepc = pc;
                mcause = 11; // Environment call from M-mode
                next_pc = mtvec;
            } else if (funct3 == 0x1) { // CSRRW
                reg_write = true;
                if (csr_addr == 0x305) {
                    write_val = mtvec;
                    mtvec = val1;
                } else if (csr_addr == 0x341) {
                    write_val = mepc;
                    mepc = val1;
                } else if (csr_addr == 0x342) {
                    write_val = mcause;
                    mcause = val1;
                }
            }
        }

        // Commit Register writes (except x0)
        if (reg_write && rd != 0) {
            regs[rd] = write_val;
        }

        // Write to log file
        if (reg_write && rd != 0) {
            trace_file << "x" << std::dec << rd 
                       << " = " << std::hex << std::setw(8) << std::setfill('0') << write_val << std::endl;
        } else if (mem_write) {
            trace_file << "mem[" << std::hex << std::setw(8) << std::setfill('0') << mem_addr 
                       << "] = " << std::hex << std::setw(8) << std::setfill('0') << mem_val << std::endl;
        }

        pc = next_pc;
    }

    trace_file.close();
    return 0;
}
