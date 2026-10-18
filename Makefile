# @brief Wrapper around cmake and ctest.
#
# Usage:
#   make help    - explain targets and variables, also plain `make`
#   make cmake   - configure build directory
#   make build   - configure if needed and build
#   make test    - configure if needed, build and run all tests
#   make test_gates - configure if needed, build and run tests of gates
#   make test_parts - configure if needed, build and run tests of parts
#   make test_blocks - configure if needed, build and run tests of blocks
#   make run R=<name regex> L=<label regex> - configure if needed, build and run selected tests
#   make list    - list tests with their labels
#   make config  - generate files from design configurations
#   make test BUILD_DIR=/tmp/dc CMAKE_ARGS="-D DARK_CIRCUIT_USE_ICARUS=ON"

# Directory of this Makefile, it has top CMakeLists.txt.
SOURCE_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
# Repository root, the same as SOURCE_DIR now; when the library is in a subdirectory
# of the repository (for example to try new code), use ROOT := $(abspath $(SOURCE_DIR)/..).
ROOT       := $(abspath $(SOURCE_DIR))

BUILD_DIR  ?= $(abspath $(ROOT)/../build)
CMAKE_ARGS ?=

# Do not print "Entering directory" for make called by cmake --build.
MAKEFLAGS += --no-print-directory

CONFIGURE := cmake -S $(SOURCE_DIR) -B $(BUILD_DIR) $(CMAKE_ARGS)

# Configure only if needed: first time, or when CMAKE_ARGS are given;
# after that cmake re-runs itself when CMakeLists.txt or flists change.
CONFIGURED := $(if $(CMAKE_ARGS),cmake,$(BUILD_DIR)/CMakeCache.txt)

# V=1 adds ctest -V: show output of every test, not only of failed tests.
CTEST := ctest --test-dir $(BUILD_DIR) --output-on-failure -j $(shell nproc) $(if $(V),-V)

# Design configurations: every rtl/design/<design>/cfg/<design>_config.yaml.
CONFIGS := $(wildcard $(SOURCE_DIR)/rtl/design/*/cfg/*_config.yaml)

# Plain `make` without a target shows help.
.DEFAULT_GOAL := help

.PHONY: cmake build test test_gates test_parts test_blocks run list config help

cmake:
	$(CONFIGURE)

$(BUILD_DIR)/CMakeCache.txt:
	$(CONFIGURE)

build: $(CONFIGURED)
	cmake --build $(BUILD_DIR) --parallel

test: build
	$(CTEST)

# Tests of gates have label gate; -L is a regex, ^gate$$ does not match label gated_clk.
test_gates: build
	$(CTEST) -L '^gate$$'

# Tests of parts have label part.
test_parts: build
	$(CTEST) -L '^part$$'

# Tests of blocks have label block.
test_blocks: build
	$(CTEST) -L '^block$$'

# Run selected tests: R=<regex> selects by test name (ctest -R),
# L=<regex> by label (ctest -L), both together select tests that match both.
run: build
	$(if $(R)$(L),,$(error make run needs R=<name regex> or L=<label regex>, see make list))
	$(CTEST) $(if $(R),-R '$(R)') $(if $(L),-L '$(L)')

# List tests: name and labels, one test per line.
# ctest -N -V prints line "Labels: ..." before line "Test #<n>: <name>", awk joins them.
list: $(CONFIGURED)
	@$(CTEST) -N -V | awk ' \
	    /^Labels:/          { sub(/^Labels: */, ""); labels = $$0 } \
	    /^ *Test +#[0-9]+:/ { printf "%-40s %s\n", $$NF, labels; labels = "" } \
	    /^Total Tests:/     { print }'

# Generate files from design configurations, run after a change in cfg/.
config:
	@for cfg in $(CONFIGS); do \
	    python3 $(SOURCE_DIR)/tools/config_gen.py --root $(SOURCE_DIR) $$cfg || exit 1; \
	done

# Help text: define ... endef is a multiline variable (like a shell here-document <<EOF),
# export puts it into the environment of the recipe, echo "$$HELP" keeps its lines.
define HELP
Wrapper around cmake and ctest of DARKCIRCUIT.

Targets:
  make help         show this help, also plain make
  make cmake        configure build directory (always runs cmake)
  make build        configure if needed and build simulations and RISC-V programs
  make test         configure if needed, build and run all tests
  make test_gates   configure if needed, build and run tests of gates (label gate)
  make test_parts   configure if needed, build and run tests of parts (label part)
  make test_blocks  configure if needed, build and run tests of blocks (label block)
  make run          configure if needed, build and run tests selected by R and L
  make list         configure if needed and list tests: name and labels of every test
  make config       generate files from design configurations: rtl/design/*/cfg/*_config.yaml

Variables:
  BUILD_DIR=<dir>      build directory, now $(BUILD_DIR)
  CMAKE_ARGS="<args>"  options for cmake, configure runs again when they are given
  R=<regex>            make run: tests with name matching regex (ctest -R)
  L=<regex>            make run: tests with label matching regex (ctest -L);
                       L=gate also matches label gated_clk, L='^gate$$' does not
  V=1                  make test*, run: show output of every test (ctest -V),
                       not only of failed tests

Examples:
  make test
  make list | grep qemu
  make run R=fifo
  make run L=block R=struct
  make run R=qemu V=1
  make run R=design_mig1_alu_prog V=1   output of Mig1 tests: path of their trace file
  make test BUILD_DIR=/tmp/dc-build
  make test CMAKE_ARGS="-D DARK_CIRCUIT_MAIN_SIMULATOR=icarus"

More in README.md: simulators, RISC-V toolchain, QEMU, running selected tests with ctest.
endef
export HELP

help:
	@echo "$$HELP"
