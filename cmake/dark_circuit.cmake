# @brief Helpers to build and run DARKCIRCUIT SystemVerilog tests.
#
# Every simulator has its own cmake/<simulator>.cmake with functions
# dc_add_<simulator>_build() (build a testbench), dc_add_<simulator>_run() (add a test
# that runs a build) and dc_add_<simulator>_test() (both, for a testbench with one test);
# functions of all simulators take the same arguments.
#
# Use of a simulator is controlled by cache variable DARK_CIRCUIT_USE_<SIMULATOR>:
#   AUTO - use it if found (default)
#   ON   - require it, fail if not found
#   OFF  - do not use it
# Example: cmake -S <source-dir> -B <build-dir> -D DARK_CIRCUIT_USE_ICARUS=OFF

# What a build tree has (Makefile D=<tree> sets them): designs of test/design (ALL,
# a list like mig1, or empty for none), and whether the tests of the library run.
set(DARK_CIRCUIT_DESIGNS ALL CACHE STRING "Designs to build and test: ALL, a list (mig1), or empty")
option(DARK_CIRCUIT_LIB_TESTS "Build and run the tests of the library (gates, parts, blocks, ...)" ON)

set(DARK_CIRCUIT_RTL_LIB    ${PROJECT_SOURCE_DIR}/rtl/lib)
set(DARK_CIRCUIT_RTL_DESIGN ${PROJECT_SOURCE_DIR}/rtl/design)

# Library modules with type parameters (<Block>T wrappers) are inside
# `ifdef DARK_CIRCUIT_ENABLE_MODULE_TYPE_PARAM: tools that support type parameters
# (Verilator, sv2v) get this macro, Icarus 11 does not (it can not parse them).
set(DARK_CIRCUIT_TYPE_PARAM_MACRO DARK_CIRCUIT_ENABLE_MODULE_TYPE_PARAM)

# dc_use_tool(<NAME> <program>...)
#
# Define cache variable DARK_CIRCUIT_USE_<NAME> (AUTO, ON or OFF),
# find every <program> into <PROGRAM>_BIN and
# set DARK_CIRCUIT_<NAME> to TRUE if the tool is used.
# <program> can be <VAR>=<program>, then it is found into <VAR>_BIN:
# riscv64-unknown-elf-gcc gives RISCV64-UNKNOWN-ELF-GCC_BIN,
# RISCV_GCC=riscv64-unknown-elf-gcc gives RISCV_GCC_BIN.
function(dc_use_tool NAME)
    set(use DARK_CIRCUIT_USE_${NAME})
    set(${use} AUTO CACHE STRING "Use ${NAME}: AUTO (if found), ON (required) or OFF")
    set_property(CACHE ${use} PROPERTY STRINGS AUTO ON OFF)

    string(TOUPPER "${${use}}" mode)
    if(NOT mode MATCHES "^(AUTO|ON|OFF)$")
        message(FATAL_ERROR "${use}=${${use}}, expected AUTO, ON or OFF")
    endif()

    if(mode STREQUAL "OFF")
        message(STATUS "${NAME}: disabled by ${use}=OFF")
        set(DARK_CIRCUIT_${NAME} FALSE PARENT_SCOPE)
        return()
    endif()

    set(found)
    set(missing)
    foreach(program IN LISTS ARGN)
        if(program MATCHES "^([A-Za-z0-9_]+)=(.+)$")
            set(var ${CMAKE_MATCH_1})
            set(program ${CMAKE_MATCH_2})
        else()
            string(TOUPPER ${program} var)
        endif()
        find_program(${var}_BIN ${program})
        if(${var}_BIN)
            list(APPEND found ${${var}_BIN})
        else()
            list(APPEND missing ${program})
        endif()
    endforeach()

    if(NOT missing)
        message(STATUS "${NAME}: enabled, ${found}")
        set(DARK_CIRCUIT_${NAME} TRUE PARENT_SCOPE)
    elseif(mode STREQUAL "ON")
        message(FATAL_ERROR "${NAME}: required by ${use}=ON, but not found: ${missing}")
    else()
        message(STATUS "${NAME}: not found (${missing}), ${NAME} tests are disabled")
        set(DARK_CIRCUIT_${NAME} FALSE PARENT_SCOPE)
    endif()
endfunction()

# dc_read_flist(<out-var> <flist>)
#
# Return absolute paths of the files listed in <flist>,
# file names in flist are relative to the flist directory.
# Line "-F <file>" includes nested flist <file>, relative to the flist directory
# like Verilator option -F does.
function(dc_read_flist OUT FLIST)
    get_filename_component(FLIST ${FLIST} ABSOLUTE)
    get_filename_component(dir ${FLIST} DIRECTORY)
    file(STRINGS ${FLIST} lines)
    set(files)
    foreach(line IN LISTS lines)
        string(STRIP "${line}" line)
        if(line STREQUAL "" OR line MATCHES "^(#|//)")
            continue()
        endif()
        if(line MATCHES "^-F[ \t]+(.+)$")
            set(nested_flist ${CMAKE_MATCH_1})
            if(NOT IS_ABSOLUTE ${nested_flist})
                set(nested_flist ${dir}/${nested_flist})
            endif()
            dc_read_flist(nested_files ${nested_flist})
            list(APPEND files ${nested_files})
        else()
            list(APPEND files ${dir}/${line})
        endif()
    endforeach()
    # Re-run cmake when flist changes.
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${FLIST})
    set(${OUT} ${files} PARENT_SCOPE)
endfunction()

# dc_parse_test_args(<name> <args>...)
#
# Parse arguments common to all dc_add_<simulator>_test() functions:
#   TOP <module> TB <tb.sv> [FLISTS <flist>...] [DEFINES <macro>...] [ARGS <arg>...]
# into T_TOP, T_TB, T_FLISTS, T_DEFINES, T_ARGS,
# and T_SOURCES that lists all flist files and then testbench:
# testbench is last because it may use packages from flists,
# and Icarus needs a package before its first use.
# ARGS are given to the simulation when the test runs, for example +hex=<file>
# that testbench reads with $value$plusargs.
macro(dc_parse_test_args NAME)
    cmake_parse_arguments(T "" "TOP;TB" "FLISTS;DEFINES;ARGS" ${ARGN})
    if(NOT T_TOP OR NOT T_TB)
        message(FATAL_ERROR "Test ${NAME}: TOP and TB are required")
    endif()
    if(T_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "Test ${NAME}: unknown arguments: ${T_UNPARSED_ARGUMENTS}")
    endif()
    get_filename_component(T_TB ${T_TB} ABSOLUTE)
    set(T_SOURCES)
    foreach(_flist IN LISTS T_FLISTS)
        dc_read_flist(_files ${_flist})
        list(APPEND T_SOURCES ${_files})
    endforeach()
    list(APPEND T_SOURCES ${T_TB})
endmacro()

# dc_parse_run_args(<test> <args>...)
#
# Parse arguments of dc_add_<simulator>_run() functions:
#   BUILD <name> [ARGS <arg>...] [LABELS <label>...] [OUTPUT <regex>]
# into R_BUILD (simulation of dc_add_<simulator>_build()), R_ARGS, R_LABELS
# (labels added to those of the simulator and of dc_test_labels()) and R_OUTPUT.
macro(dc_parse_run_args TEST)
    cmake_parse_arguments(R "" "BUILD;OUTPUT" "ARGS;LABELS" ${ARGN})
    if(NOT R_BUILD)
        message(FATAL_ERROR "Test ${TEST}: BUILD is required")
    endif()
    if(R_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "Test ${TEST}: unknown arguments: ${R_UNPARSED_ARGUMENTS}")
    endif()
endmacro()

# dc_run_command(<out-var> <command>...)
#
# Command of a test that runs simulation <command>: <command> itself, the test passes
# with exit code 0. With R_OUTPUT of dc_parse_run_args() it is cmake -P run_check.cmake,
# which also checks that the output matches R_OUTPUT (CTest alone checks either exit
# code or output).
function(dc_run_command OUT)
    if("${R_OUTPUT}" STREQUAL "")
        set(${OUT} ${ARGN} PARENT_SCOPE)
    else()
        set(${OUT} ${CMAKE_COMMAND} -D "OUTPUT=${R_OUTPUT}"
                   -P ${PROJECT_SOURCE_DIR}/cmake/run_check.cmake -- ${ARGN} PARENT_SCOPE)
    endif()
endfunction()

# dc_test_labels(<out-var>)
#
# Return labels of a test added in current directory under test/:
# first directory (gate, sim, part, ...) and, if different, the last directory.
# For example test/part/carry_save_adder gives labels part and carry_save_adder.
function(dc_test_labels OUT)
    file(RELATIVE_PATH rel ${PROJECT_SOURCE_DIR}/test ${CMAKE_CURRENT_SOURCE_DIR})
    string(REPLACE "/" ";" dirs "${rel}")
    set(labels)
    if(dirs)
        list(GET dirs 0 first)
        list(GET dirs -1 last)
        list(APPEND labels ${first})
        if(NOT last STREQUAL first)
            list(APPEND labels ${last})
        endif()
    endif()
    set(${OUT} ${labels} PARENT_SCOPE)
endfunction()

include(${CMAKE_CURRENT_LIST_DIR}/icarus.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/verilator.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/sv2v.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/yosys.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/riscv.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/qemu.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/config.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/fetch.cmake)

# Main simulator runs tests that need only one simulator, like tests of parts.
# Cache variable DARK_CIRCUIT_MAIN_SIMULATOR selects it:
#   AUTO      - first used simulator of verilator, icarus (default)
#   verilator - Verilator, fail if it is not used
#   icarus    - Icarus Verilog, fail if it is not used
set(DARK_CIRCUIT_MAIN_SIMULATOR AUTO CACHE STRING
    "Simulator for tests that run on one simulator: AUTO, verilator or icarus")
set_property(CACHE DARK_CIRCUIT_MAIN_SIMULATOR PROPERTY STRINGS AUTO verilator icarus)

set(DARK_CIRCUIT_MAINSIM)
string(TOLOWER "${DARK_CIRCUIT_MAIN_SIMULATOR}" main_simulator)
if(main_simulator STREQUAL "auto")
    foreach(simulator IN ITEMS verilator icarus)
        string(TOUPPER ${simulator} SIMULATOR)
        if(DARK_CIRCUIT_${SIMULATOR})
            set(DARK_CIRCUIT_MAINSIM ${simulator})
            break()
        endif()
    endforeach()
elseif(main_simulator MATCHES "^(verilator|icarus)$")
    string(TOUPPER ${main_simulator} SIMULATOR)
    if(NOT DARK_CIRCUIT_${SIMULATOR})
        message(FATAL_ERROR "DARK_CIRCUIT_MAIN_SIMULATOR=${DARK_CIRCUIT_MAIN_SIMULATOR}, but ${SIMULATOR} is not used")
    endif()
    set(DARK_CIRCUIT_MAINSIM ${main_simulator})
else()
    message(FATAL_ERROR "DARK_CIRCUIT_MAIN_SIMULATOR=${DARK_CIRCUIT_MAIN_SIMULATOR}, expected AUTO, verilator or icarus")
endif()

if(DARK_CIRCUIT_MAINSIM)
    message(STATUS "MAIN SIMULATOR: ${DARK_CIRCUIT_MAINSIM}")
else()
    message(STATUS "MAIN SIMULATOR: none, tests on main simulator are disabled")
endif()

# dc_add_mainsim_test(<name> TOP <module> TB <tb.sv>
#                     [FLISTS <flist>...] [DEFINES <macro>...] [ARGS <arg>...])
#
# Add test that runs on the main simulator only,
# it calls dc_add_<simulator>_test() of the main simulator.
# Does nothing if there is no main simulator.
function(dc_add_mainsim_test NAME)
    if(DARK_CIRCUIT_MAINSIM)
        cmake_language(CALL dc_add_${DARK_CIRCUIT_MAINSIM}_test ${NAME} ${ARGN})
    endif()
endfunction()
