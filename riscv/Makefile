prefix = $(shell pwd)
# Folder Path
src = $(prefix)/src
testspace = $(prefix)/testspace

sim_testcase = $(prefix)/testcase/sim
fpga_testcase = $(prefix)/testcase/fpga

sim = $(prefix)/sim
fpga = $(prefix)/fpga
riscv_toolchain = /home/Modem514/cpu-tool-chain/
riscv_bin = $(riscv_toolchain)/bin
sys = $(prefix)/sys

usbport = ttyS4

_no_testcase_name_check:
	@$(if $(strip $(name)),, echo 'Missing Testcase Name')
	@$(if $(strip $(name)),, exit 1)

# All build result are put at testspace
build_sim:
	@cd $(src) && iverilog -o $(testspace)/test $(sim)/testbench.v $(src)/common/block_ram/*.v $(src)/common/fifo/*.v $(src)/common/uart/*.v $(src)/*.v

build_sim_test: _no_testcase_name_check
	@$(riscv_bin)/riscv32-unknown-elf-as -o $(sys)/rom.o -march=rv32i $(sys)/rom.s
	@cp $(sim_testcase)/*$(name)*.c $(testspace)/test.c
	@$(riscv_bin)/riscv32-unknown-elf-gcc -o $(testspace)/test.o -I $(sys) -c $(testspace)/test.c -O2 -march=rv32i -mabi=ilp32 -Wall
	@$(riscv_bin)/riscv32-unknown-elf-ld -T $(sys)/memory.ld $(sys)/rom.o $(testspace)/test.o -L $(riscv_toolchain)/riscv32-unknown-elf/lib/ -L $(riscv_toolchain)/lib/gcc/riscv32-unknown-elf/10.1.0/ -lc -lgcc -lm -lnosys -o $(testspace)/test.om
	@$(riscv_bin)/riscv32-unknown-elf-objcopy -O verilog $(testspace)/test.om $(testspace)/test.data
	@$(riscv_bin)/riscv32-unknown-elf-objdump -D $(testspace)/test.om > $(testspace)/test.dump
	@$(shell test -f $(testspace)/test.in && rm $(testspace)/test.in)
	@$(shell test -f $(testspace)/test.ans && rm $(testspace)/test.ans)
	@$(shell test -f $(sim_testcase)/*$(name)*.in && cp $(sim_testcase)/*$(name)*.in $(testspace)/test.in) 
	@$(shell test -f $(sim_testcase)/*$(name)*.ans && cp $(sim_testcase)/*$(name)*.ans $(testspace)/test.ans)

run_sim:
	@cd $(testspace) && ./test

test_sim: build_sim build_sim_test run_sim

build_fpga: 
	@cd $(fpga) && g++ controller.cpp -std=c++14 -I /tmp/usr/local/include/ -L /tmp/usr/local/lib/ -lserial -lpthread -o $(testspace)/ctrl

build_fpga_test: _no_testcase_name_check
	@$(riscv_bin)/riscv32-unknown-elf-as -o $(sys)/rom.o -march=rv32i $(sys)/rom.s
	@cp $(fpga_testcase)/*$(name)*.c $(testspace)/test.c
	@$(riscv_bin)/riscv32-unknown-elf-gcc -o $(testspace)/test.o -I $(sys) -c $(testspace)/test.c -O2 -march=rv32i -mabi=ilp32 -Wall
	@$(riscv_bin)/riscv32-unknown-elf-ld -T $(sys)/memory.ld $(sys)/rom.o $(testspace)/test.o -L $(riscv_toolchain)/riscv32-unknown-elf/lib/ -L $(riscv_toolchain)/lib/gcc/riscv32-unknown-elf/10.1.0/ -lc -lgcc -lm -lnosys -o $(testspace)/test.om
	@$(riscv_bin)/riscv32-unknown-elf-objcopy -O verilog $(testspace)/test.om $(testspace)/test.data
	@$(riscv_bin)/riscv32-unknown-elf-objcopy -O binary $(testspace)/test.om $(testspace)/test.bin
	@$(riscv_bin)/riscv32-unknown-elf-objdump -D $(testspace)/test.om > $(testspace)/test.dump
	@$(shell test -f $(testspace)/test.in && rm $(testspace)/test.in)
	@$(shell test -f $(testspace)/test.ans && rm $(testspace)/test.ans)
	@$(shell test -f $(fpga_testcase)/*$(name)*.in && cp $(fpga_testcase)/*$(name)*.in $(testspace)/test.in)
	@$(shell test -f $(fpga_testcase)/*$(name)*.ans && cp $(fpga_testcase)/*$(name)*.ans $(testspace)/test.ans)

run_fpga: 
	@$(testspace)/ctrl $(testspace)/test.bin $(testspace)/test.in /dev/$(usbport) -I

test_fpga: build_fpga build_fpga_test run_fpga

clear:
	@rm $(sys)/rom.o $(testspace)/test*

.PHONY: _no_testcase_name_check build_sim build_sim_test run_sim clear test_sim build_fpga build_fpga_test run_fpga clear test_fpga

