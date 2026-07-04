#!/bin/bash
# =================================================================
# verify.sh  –  Verification Script for RISC-V Pipelined Processor
# =================================================================

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "====================================================="
echo "   RISC-V Processor Automated Verification Suite"
echo "====================================================="

# 1. Run tb_top.v
echo -e "\n[1/6] Running Basic Pipelining Testbench (tb_top)..."
iverilog -o sim top.v tb_top.v
if [ $? -ne 0 ]; then
    echo -e "${RED}Compilation failed for tb_top${NC}"
    exit 1
fi
./sim | tail -n 25

# 2. Run tb_top_hazard.v
echo -e "\n[2/6] Running Hazard & Branch Squash Testbench (tb_top_hazard)..."
iverilog -o sim_hazard tb_top_hazard.v
if [ $? -ne 0 ]; then
    echo -e "${RED}Compilation failed for tb_top_hazard${NC}"
    exit 1
fi
./sim_hazard | tail -n 25

# 3. Run tb_upgrades.v
echo -e "\n[3/6] Running Upgrades Verification Testbench (tb_upgrades)..."
iverilog -o sim_upgrades tb_upgrades.v
if [ $? -ne 0 ]; then
    echo -e "${RED}Compilation failed for tb_upgrades${NC}"
    exit 1
fi
./sim_upgrades | tail -n 16

# 4. Run tb_soc.v (SoC MMIO Mode)
echo -e "\n[4/6] Running SoC UART & Timer Testbench (tb_soc)..."
iverilog -o sim_soc tb_soc.v
if [ $? -ne 0 ]; then
    echo -e "${RED}Compilation failed for tb_soc${NC}"
    exit 1
fi
./sim_soc

# 5. Run tb_all.v
echo -e "\n[5/6] Running Unified Comprehensive Testbench (tb_all)..."
iverilog -s tb_all -o sim_all tb_all.v
if [ $? -ne 0 ]; then
    echo -e "${RED}Compilation failed for tb_all${NC}"
    exit 1
fi
./sim_all | tail -n 16

# 6. Run compare.py (Co-Simulation Verification)
echo -e "\n[6/6] Running ISS Co-Simulation Verification (compare.py)..."
python3 compare.py
if [ $? -ne 0 ]; then
    echo -e "${RED}ISS Co-Simulation Verification failed!${NC}"
    exit 1
fi

# Cleanup simulation binaries
rm -f sim sim_hazard sim_upgrades sim_soc sim_all

echo -e "\n====================================================="
echo -e "                 Verification Done"
echo -e "====================================================="
