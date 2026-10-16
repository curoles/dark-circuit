# @brief Wrapper around cmake and ctest.
#
# Usage:
#   make help    - explain targets and variables, also plain `make`
#   make cmake   - configure build directory
#   make build   - configure if needed and build
#   make test    - configure if needed, build and run all tests
#   make test_parts - configure if needed, build and run tests of parts
#   make test_blocks - configure if needed, build and run tests of blocks
#   make list    - list tests with their labels
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

CTEST := ctest --test-dir $(BUILD_DIR) --output-on-failure -j $(shell nproc)

# Plain `make` without a target shows help.
.DEFAULT_GOAL := help

.PHONY: cmake build test test_parts test_blocks list help

cmake:
	$(CONFIGURE)

$(BUILD_DIR)/CMakeCache.txt:
	$(CONFIGURE)

build: $(CONFIGURED)
	cmake --build $(BUILD_DIR) --parallel

test: build
	$(CTEST)

# Tests of parts have label part.
test_parts: build
	$(CTEST) -L part

# Tests of blocks have label block.
test_blocks: build
	$(CTEST) -L block

# List tests: name and labels, one test per line.
# ctest -N -V prints line "Labels: ..." before line "Test #<n>: <name>", awk joins them.
list: $(CONFIGURED)
	@$(CTEST) -N -V | awk ' \
	    /^Labels:/          { sub(/^Labels: */, ""); labels = $$0 } \
	    /^ *Test +#[0-9]+:/ { printf "%-40s %s\n", $$NF, labels; labels = "" } \
	    /^Total Tests:/     { print }'

# Help text: define ... endef is a multiline variable (like a shell here-document <<EOF),
# export puts it into the environment of the recipe, echo "$$HELP" keeps its lines.
define HELP
Wrapper around cmake and ctest of DARKCIRCUIT.

Targets:
  make help         show this help, also plain make
  make cmake        configure build directory (always runs cmake)
  make build        configure if needed and build simulations and RISC-V programs
  make test         configure if needed, build and run all tests
  make test_parts   configure if needed, build and run tests of parts (label part)
  make test_blocks  configure if needed, build and run tests of blocks (label block)
  make list         configure if needed and list tests: name and labels of every test

Variables:
  BUILD_DIR=<dir>      build directory, now $(BUILD_DIR)
  CMAKE_ARGS="<args>"  options for cmake, configure runs again when they are given

Examples:
  make test
  make list | grep qemu
  make test BUILD_DIR=/tmp/dc-build
  make test CMAKE_ARGS="-D DARK_CIRCUIT_MAIN_SIMULATOR=icarus"

More in README.md: simulators, RISC-V toolchain, QEMU, running selected tests with ctest.
endef
export HELP

help:
	@echo "$$HELP"
