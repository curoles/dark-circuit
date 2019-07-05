# Makefile to build Fast Incrementor TB with Verilator.
# Author: Igor Lesik 2019
#

ifeq (, $(shell which verilator))
$(error "No verilator in $$PATH, consider doing export PATH=$$PATH:<path_to_verilator>")
endif

VERILATOR := $(shell which verilator)
VERILATOR_ROOT_ := $(dir $(VERILATOR))/..

TB_MAIN_CPP := $(SRC)/sim_main.cpp

TB_TOP := tb_top

VERILATOR_PARAMS := -O3 -Wall -Wno-lint --assert
VERILATOR_PARAMS += --cc --compiler gcc
VERILATOR_PARAMS += --exe $(TB_MAIN_CPP) --clk clk
VERILATOR_PARAMS += -y ../rtl -y ../../../lib
VERILATOR_PARAMS += -CFLAGS "-O3"
VERILATOR_PARAMS += $(TB_TOP)

VMAKE := make -C ./obj_dir

.PHONY: tb_exe
tb_exe: export VERILATOR_ROOT=$(VERILATOR_ROOT_)
tb_exe: tb
	$(VMAKE) -j -f V$(TB_TOP).mk $(CFLAGS) V$(TB_TOP)

.PHONY: tb
tb: $(TB_MAIN_CPP)
	$(VERILATOR) $(VERILATOR_PARAMS)

.PHONY: run_test
run_test: tb_exe
	./obj_dir/V$(TB_TOP)


.PHONY: clean
clean:
	rm -rf ./obj_dir

