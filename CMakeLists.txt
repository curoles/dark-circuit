cmake_minimum_required(VERSION 3.20)

# @brief cmake script to build and test DARKCIRCUIT library.
#
# Build outside of the source tree:
#   cmake -S . -B ../build
#   cmake --build ../build
#   ctest --test-dir ../build

project(DARKCIRCUIT NONE)

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_BINARY_DIR)
    message(FATAL_ERROR "In-source build is not allowed, use: cmake -S <source-dir> -B <build-dir>")
endif()

include(${PROJECT_SOURCE_DIR}/cmake/dark_circuit.cmake)

enable_testing()

add_subdirectory(test)
