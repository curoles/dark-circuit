# @brief QEMU tests: run RISC-V programs on QEMU with semihosting.
#
# QEMU is a reference for RISC-V programs: what runs on QEMU should run on our CPUs.
# Use of QEMU is controlled by cache variable DARK_CIRCUIT_USE_QEMU (AUTO, ON or OFF).

dc_use_tool(QEMU QEMU_RISCV32=qemu-system-riscv32)

# dc_add_qemu_test(<name> ELF <file> [EXIT_CODE <n>] [OUTPUT <regex>]
#                  [MACHINE <machine>] [TIMEOUT <seconds>])
#
# Add CTest test <name>.qemu that runs <file> on qemu-system-riscv32 with semihosting
# and passes when the program exits with EXIT_CODE (default 0) and its output
# matches OUTPUT (when given). MACHINE is QEMU -M, default virt (RAM at 0x80000000).
# TIMEOUT stops a program that never exits, default 10 seconds.
# Labels: qemu and labels of dc_test_labels().
# Does nothing if QEMU is not used.
function(dc_add_qemu_test NAME)
    if(NOT DARK_CIRCUIT_QEMU)
        return()
    endif()
    cmake_parse_arguments(Q "" "ELF;EXIT_CODE;OUTPUT;MACHINE;TIMEOUT" "" ${ARGN})
    if(NOT Q_ELF)
        message(FATAL_ERROR "QEMU test ${NAME}: ELF is required")
    endif()
    if(Q_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "QEMU test ${NAME}: unknown arguments: ${Q_UNPARSED_ARGUMENTS}")
    endif()
    if(NOT DEFINED Q_EXIT_CODE)
        set(Q_EXIT_CODE 0)
    endif()
    if(NOT Q_MACHINE)
        set(Q_MACHINE virt)
    endif()
    if(NOT Q_TIMEOUT)
        set(Q_TIMEOUT 10)
    endif()

    # The test runs cmake as a script interpreter: CMAKE_COMMAND is the path of the
    # cmake program configuring this build, -D sets variables for the script and
    # -P runs qemu_run.cmake, which starts QEMU and checks its exit code and output
    # (CTest alone checks either exit code or output, not both).
    # CMAKE_CURRENT_FUNCTION_LIST_DIR is the directory of this file, cmake/.
    set(test ${NAME}.qemu)
    add_test(NAME ${test}
        COMMAND ${CMAKE_COMMAND}
            -D QEMU=${QEMU_RISCV32_BIN} -D MACHINE=${Q_MACHINE} -D ELF=${Q_ELF}
            -D EXIT_CODE=${Q_EXIT_CODE} -D OUTPUT=${Q_OUTPUT} -D TIMEOUT=${Q_TIMEOUT}
            -P ${CMAKE_CURRENT_FUNCTION_LIST_DIR}/qemu_run.cmake)
    dc_test_labels(labels)
    set_tests_properties(${test} PROPERTIES LABELS "qemu;${labels}")
endfunction()
