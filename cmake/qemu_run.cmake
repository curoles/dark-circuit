# @brief Run RISC-V program on QEMU with semihosting, check exit code and output.
#
# cmake -D QEMU=<qemu> -D MACHINE=<machine> -D ELF=<file> -D EXIT_CODE=<n>
#       -D OUTPUT=<regex> -D TIMEOUT=<seconds> -P qemu_run.cmake
# Fails (cmake exit code not 0) when QEMU exit code is not EXIT_CODE,
# output does not match OUTPUT (if not empty) or QEMU runs longer than TIMEOUT.

execute_process(
    COMMAND ${QEMU} -M ${MACHINE} -bios none -kernel ${ELF} -nographic
            -semihosting-config enable=on,target=native -monitor none -serial none
    TIMEOUT ${TIMEOUT}
    RESULT_VARIABLE result
    OUTPUT_VARIABLE output
    ERROR_VARIABLE  output
)
message("${output}")
if(NOT result STREQUAL "${EXIT_CODE}")
    message(FATAL_ERROR "QEMU exit code: ${result}, expected: ${EXIT_CODE}")
endif()
if(NOT OUTPUT STREQUAL "" AND NOT output MATCHES "${OUTPUT}")
    message(FATAL_ERROR "QEMU output does not match: ${OUTPUT}")
endif()
