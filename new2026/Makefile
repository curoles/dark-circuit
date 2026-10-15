# @brief Wrapper around cmake and ctest.
#
# Usage:
#   make cmake   - configure build directory
#   make build   - configure if needed and build
#   make test    - configure if needed, build and run all tests
#   make test BUILD_DIR=/tmp/dc CMAKE_ARGS="-D DARK_CIRCUIT_USE_ICARUS=ON"

# Directory of this Makefile, it has top CMakeLists.txt.
SOURCE_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
# Repository root; when this directory becomes the root, use ROOT := $(SOURCE_DIR).
ROOT       := $(abspath $(SOURCE_DIR)/..)

BUILD_DIR  ?= $(abspath $(ROOT)/../build)
CMAKE_ARGS ?=

# Do not print "Entering directory" for make called by cmake --build.
MAKEFLAGS += --no-print-directory

CONFIGURE := cmake -S $(SOURCE_DIR) -B $(BUILD_DIR) $(CMAKE_ARGS)

# Configure only if needed: first time, or when CMAKE_ARGS are given;
# after that cmake re-runs itself when CMakeLists.txt or flists change.
CONFIGURED := $(if $(CMAKE_ARGS),cmake,$(BUILD_DIR)/CMakeCache.txt)

.PHONY: cmake build test

cmake:
	$(CONFIGURE)

$(BUILD_DIR)/CMakeCache.txt:
	$(CONFIGURE)

build: $(CONFIGURED)
	cmake --build $(BUILD_DIR) --parallel

test: build
	ctest --test-dir $(BUILD_DIR) --output-on-failure
