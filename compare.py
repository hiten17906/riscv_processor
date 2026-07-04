#!/usr/bin/env python3
# =================================================================
# compare.py  –  RISC-V Co-Simulation Trace Verification Script
# =================================================================
import os
import sys
import subprocess

# Unified test program matching tb_all.v
PROGRAM = [
    "00a00093", # addi x1, x0, 10
    "01400113", # addi x2, x0, 20
    "00500193", # addi x3, x0, 5
    "002082b3", # add x5, x1, x2        (x5 = 30)
    "40310333", # sub x6, x2, x3        (x6 = 15)
    "0030f3b3", # and x7, x1, x3        (x7 = 0)
    "0030e433", # or  x8, x1, x3        (x8 = 15)
    "01f2f493", # andi x9, x5, 31       (x9 = 30)
    "00136513", # ori  x10, x6, 1       (x10 = 15)
    "0011a5b3", # slt  x11, x3, x1      (x11 = 1)
    "0641a613", # slti x12, x3, 100     (x12 = 1)
    "00122023", # sw   x1, 0(x4)        (mem[0] = 10)
    "00022803", # lw   x16, 0(x4)       (x16 = 10)
    "002808b3", # add  x17, x16, x2     (x17 = 30)
    "00300313", # addi x6, x0, 3        (re-write x6 = 3)
    "00300393", # addi x7, x0, 3        (re-write x7 = 3)
    "00730663", # beq  x6, x7, +12      (taken to index 20)
    "06300413", # addi x8,  x0, 99      -- SQUASHED
    "05800493", # addi x9,  x0, 88      -- SQUASHED
    "00000013", # NOP (index 19)
    "02a00913", # addi x18, x0, 42      (x18 = 42)
    "00400593", # addi x11, x0, 4       (re-write x11 = 4)
    "00700613", # addi x12, x0, 7       (re-write x12 = 7)
    "00c5a023", # sw   x12, 0(x11)      (mem[1] = 7)
    "0005a683", # lw   x13, 0(x11)      (x13 = 7)
    "00069663", # bne  x13, x0, +12     (taken to index 29)
    "03700713", # addi x14, x0, 55      -- SQUASHED
    "04200793", # addi x15, x0, 66      -- SQUASHED
    "00000013", # NOP (index 28)
    "00a00993", # addi x19, x0, 10
    "00300a13", # addi x20, x0, 3
    "03498ab3", # mul  x21, x19, x20    (x21 = 30)
    "0349cb33", # div  x22, x19, x20    (x22 = 3)
    "0349ebb3", # rem  x23, x19, x20    (x23 = 1)
    "0b400c93", # addi x25, x0, 180     (trap vector = index 45)
    "305c9073", # csrrw x0, mtvec, x25  (mtvec = 180)
    "00000013", # NOP
    "00000013",
    "00000013",
    "00000073", # ecall (Trap!)
    "06300c13", # addi x24, x0, 99      -- SQUASHED
    "00000013", # NOP
    "00000013",
    "00000013",
    "00000013",
    "00500d13", # addi x26, x0, 5       (x26 = 5)
    "00c0006f", # jal  x0, +12          (jump out to PC=200 = index 50)
    "00000013", # NOP
    "00000013",
    "00000013",
    "00200d93", # addi x27, x0, 2
    "00000e13", # addi x28, x0, 0
    "00100e93", # addi x29, x0, 1
    "01de0e33", # add  x28, x28, x29    (increments x28)
    "ffbe1ee3", # bne  x28, x27, -4     (branch to index 53 if x28!=x27)
    "0000006f", # halt self-loop (jal x0, 0)
    "00000013",
    "00000013"
]

def print_banner(msg):
    print("=" * 60)
    print(f"   {msg}")
    print("=" * 60)

def main():
    # 1. Write program.hex
    print("[1/5] Writing program.hex...")
    with open("program.hex", "w") as f:
        for instr in PROGRAM:
            f.write(f"{instr}\n")

    # 2. Compile C++ Golden ISS
    print("[2/5] Compiling C++ Golden ISS...")
    cmd_compile_cpp = ["g++", "-O3", "-o", "riscv_iss", "riscv_iss.cpp"]
    res = subprocess.run(cmd_compile_cpp)
    if res.returncode != 0:
        print("❌ Error: C++ Compilation failed!")
        sys.exit(1)

    # 3. Run C++ Golden ISS
    print("[3/5] Simulating on C++ Golden ISS...")
    res = subprocess.run(["./riscv_iss"])
    if res.returncode != 0:
        print("❌ Error: C++ ISS Execution failed!")
        sys.exit(1)

    # 4. Compile and Run Verilog CPU
    print("[4/5] Compiling and Simulating Verilog CPU...")
    cmd_compile_v = ["iverilog", "-s", "tb_cosim", "-o", "sim_cosim", "tb_cosim.v"]
    res = subprocess.run(cmd_compile_v)
    if res.returncode != 0:
        print("❌ Error: Verilog Compilation failed!")
        sys.exit(1)

    res = subprocess.run(["./sim_cosim"])
    if res.returncode != 0:
        print("❌ Error: Verilog Simulation failed!")
        sys.exit(1)

    # 5. Compare traces
    print("[5/5] Performing Co-Simulation Trace Check...")
    
    with open("golden_trace.log") as f:
        golden_lines = [line.strip() for line in f if line.strip()]
        
    with open("cpu_trace.log") as f:
        cpu_lines = [line.strip() for line in f if line.strip()]

    # Compare
    mismatches = 0
    max_len = max(len(golden_lines), len(cpu_lines))
    
    for i in range(max_len):
        g_line = golden_lines[i] if i < len(golden_lines) else "<EOF>"
        c_line = cpu_lines[i] if i < len(cpu_lines) else "<EOF>"
        
        if g_line != c_line:
            if mismatches < 10:
                print(f"❌ Mismatch at cycle/instruction {i+1}:")
                print(f"   Golden ISS : {g_line}")
                print(f"   Verilog CPU: {c_line}")
            mismatches += 1

    # Cleanup
    if os.path.exists("riscv_iss"): os.remove("riscv_iss")
    if os.path.exists("sim_cosim"): os.remove("sim_cosim")

    if mismatches == 0:
        print_banner("🎉 CO-SIMULATION SUCCESS: traces match 100%!")
        print(f"Successfully verified {len(golden_lines)} architectural events.")
        sys.exit(0)
    else:
        print_banner(f"❌ CO-SIMULATION FAIL: {mismatches} mismatches found!")
        sys.exit(1)

if __name__ == "__main__":
    main()
