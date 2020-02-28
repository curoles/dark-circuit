bold   := $(shell tput bold)
red    := $(shell tput setaf 1)
green  := $(shell tput setaf 2)
yellow := $(shell tput setaf 3)
normal := $(shell tput sgr0)


ifeq (, $(shell which verilator))
$(error "$(bold)$(red)No verilator in $$PATH, do export PATH=$$PATH:<path_to_verilator>$(normal)")
endif

VERILATOR := $(shell which verilator)
VERILATOR_ROOT_ := $(dir $(VERILATOR))/..

TB_MAIN_CPP ?= $(SRC)/sim_main.cpp

TB_TOP ?= tb_top

LIB_TYPE ?= generic

VERILATOR_PARAMS := -O3 -Wall -Wno-lint --assert
VERILATOR_PARAMS += --cc --compiler gcc
VERILATOR_PARAMS += --exe $(TB_MAIN_CPP) --clk clk
VERILATOR_PARAMS += -y $(SRC)/../rtl -y $(SRC)/../../../lib/$(LIB_TYPE)
VERILATOR_PARAMS += -CFLAGS "-O3"
VERILATOR_PARAMS += --top-module $(TB_TOP) $(SRC)/$(TB_TOP).sv

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

