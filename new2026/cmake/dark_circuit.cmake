# @brief Helpers to build and run DARKCIRCUIT SystemVerilog tests.
#
# Every simulator has its own cmake/<simulator>.cmake with function
# dc_add_<simulator>_test(), all such functions take the same arguments.
#
# Use of a simulator is controlled by cache variable DARK_CIRCUIT_USE_<SIMULATOR>:
#   AUTO - use it if found (default)
#   ON   - require it, fail if not found
#   OFF  - do not use it
# Example: cmake -S <source-dir> -B <build-dir> -D DARK_CIRCUIT_USE_ICARUS=OFF

set(DARK_CIRCUIT_RTL_LIB ${PROJECT_SOURCE_DIR}/rtl/lib)

# dc_use_tool(<NAME> <program>...)
#
# Define cache variable DARK_CIRCUIT_USE_<NAME> (AUTO, ON or OFF),
# find every <program> into <PROGRAM>_BIN and
# set DARK_CIRCUIT_<NAME> to TRUE if the tool is used.
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
        string(TOUPPER ${program} var)
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
        list(APPEND files ${dir}/${line})
    endforeach()
    # Re-run cmake when flist changes.
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${FLIST})
    set(${OUT} ${files} PARENT_SCOPE)
endfunction()

# dc_parse_test_args(<name> <args>...)
#
# Parse arguments common to all dc_add_<simulator>_test() functions:
#   TOP <module> TB <tb.sv> [FLISTS <flist>...] [DEFINES <macro>...]
# into T_TOP, T_TB, T_FLISTS, T_DEFINES,
# and T_SOURCES that lists testbench and all flist files.
macro(dc_parse_test_args NAME)
    cmake_parse_arguments(T "" "TOP;TB" "FLISTS;DEFINES" ${ARGN})
    if(NOT T_TOP OR NOT T_TB)
        message(FATAL_ERROR "Test ${NAME}: TOP and TB are required")
    endif()
    if(T_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "Test ${NAME}: unknown arguments: ${T_UNPARSED_ARGUMENTS}")
    endif()
    get_filename_component(T_TB ${T_TB} ABSOLUTE)
    set(T_SOURCES ${T_TB})
    foreach(_flist IN LISTS T_FLISTS)
        dc_read_flist(_files ${_flist})
        list(APPEND T_SOURCES ${_files})
    endforeach()
endmacro()

include(${CMAKE_CURRENT_LIST_DIR}/icarus.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/verilator.cmake)
