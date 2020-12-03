cmake_minimum_required (VERSION 3.10)

# @copyright Igor Lesik 2020
# @authors   Igor Lesik 2019-2020
# @brief     cmake script to build DARKCIRCUIT.

project(DARKCIRCUIT)
# CMakeLists files in this project can refer to the root source directory
# of the project as ${DARKCIRCUIT_SOURCE_DIR} and to the root binary directory
# of the project as ${DARKCIRCUIT_BINARY_DIR}.

# Requires C++17.
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Configuration options
# Verilator is default Verilog compiler, to turn it off:
# cmake -D USE_VERILATOR=OFF ../dark-circuit/
option(USE_VERILATOR "Use Verilator to compile" ON)
option(USE_XCELIUM "Use Cadence Xcelium to compile and simulate" OFF)

# Compiler options.
set(DARKCIRCUIT_M_CFLAGS "-march=native")
set(DARKCIRCUIT_W_CFLAGS "-Werror -Wall -Wextra")
set(DARKCIRCUIT_O_CFLAGS "-O3 -flto")
set(DARKCIRCUIT_COMMON_CXX_FLAGS "${DARKCIRCUIT_M_CFLAGS} ${DARKCIRCUIT_W_CFLAGS} ${DARKCIRCUIT_O_FLAG}")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${DARKCIRCUIT_COMMON_CXX_FLAGS}")

# Install inside the build directory.
set(CMAKE_INSTALL_PREFIX ${CMAKE_BINARY_DIR}/install)

enable_testing()

add_subdirectory(docs)
add_subdirectory(test)

# Log CMake variables.
MESSAGE( STATUS "CMAKE_C_COMPILER    : " ${CMAKE_C_COMPILER} )
MESSAGE( STATUS "CMAKE_CXX_COMPILER  : " ${CMAKE_CXX_COMPILER} )
MESSAGE( STATUS "CMAKE_CXX_FLAGS     : " ${CMAKE_CXX_FLAGS} )
MESSAGE( STATUS "CMAKE_INSTALL_PREFIX: " ${CMAKE_INSTALL_PREFIX} )
MESSAGE( STATUS "USE VERILATOR       : " ${USE_VERILATOR} )
MESSAGE( STATUS "USE XCELIUM         : " ${USE_XCELIUM} )
