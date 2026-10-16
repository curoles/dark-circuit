# @brief RISC-V programs for tests.
#
# Programs are built with the RISC-V GNU toolchain (gcc, objcopy, objdump)
# into Verilog hex files that SimRAM and SimROM load().
# Use of the toolchain is controlled by cache variable DARK_CIRCUIT_USE_RISCV
# (AUTO, ON or OFF), names of its programs start with DARK_CIRCUIT_RISCV_PREFIX.

set(DARK_CIRCUIT_RISCV_PREFIX riscv64-unknown-elf- CACHE STRING
    "RISC-V GNU toolchain prefix: riscv64-unknown-elf- (Ubuntu), riscv32-unknown-elf-, riscv-none-elf- (xPack), ...")

# Programs found with another prefix are forgotten when the prefix changes.
if(NOT DARK_CIRCUIT_RISCV_PREFIX STREQUAL "${DC_RISCV_PREFIX_FOUND}")
    unset(RISCV_GCC_BIN CACHE)
    unset(RISCV_OBJCOPY_BIN CACHE)
    unset(RISCV_OBJDUMP_BIN CACHE)
    set(DC_RISCV_PREFIX_FOUND ${DARK_CIRCUIT_RISCV_PREFIX} CACHE INTERNAL "Prefix of found RISC-V programs")
endif()

dc_use_tool(RISCV RISCV_GCC=${DARK_CIRCUIT_RISCV_PREFIX}gcc
                  RISCV_OBJCOPY=${DARK_CIRCUIT_RISCV_PREFIX}objcopy
                  RISCV_OBJDUMP=${DARK_CIRCUIT_RISCV_PREFIX}objdump)

# dc_add_riscv_program(<name> SOURCES <file>...
#                      [ARCH <march>] [ABI <mabi>]
#                      [LINK_FLAGS <flag>...] [FLAGS <flag>...])
#
# Build bare-metal program <name>.elf from SOURCES in the current build directory,
# then <name>.hex (objcopy -O verilog: byte addresses and bytes, the format of
# SimRAM load()) and <name>.dis (objdump -d) to read the code.
#   ARCH       -march, default rv32i
#   ABI        -mabi, default ilp32
#   LINK_FLAGS link options, default -Wl,-Ttext=0 (code at address 0);
#              for example -T <linker script> to place code and data
#   FLAGS      more gcc options, for example -I<dir> or -D<macro>
# Does nothing if the RISC-V toolchain is not used.
function(dc_add_riscv_program NAME)
    if(NOT DARK_CIRCUIT_RISCV)
        return()
    endif()
    cmake_parse_arguments(P "" "ARCH;ABI" "SOURCES;LINK_FLAGS;FLAGS" ${ARGN})
    if(NOT P_SOURCES)
        message(FATAL_ERROR "RISC-V program ${NAME}: SOURCES are required")
    endif()
    if(P_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "RISC-V program ${NAME}: unknown arguments: ${P_UNPARSED_ARGUMENTS}")
    endif()
    if(NOT P_ARCH)
        set(P_ARCH rv32i)
    endif()
    if(NOT P_ABI)
        set(P_ABI ilp32)
    endif()
    if(NOT P_LINK_FLAGS)
        set(P_LINK_FLAGS -Wl,-Ttext=0)
    endif()

    set(sources)
    foreach(source IN LISTS P_SOURCES)
        get_filename_component(source ${source} ABSOLUTE)
        list(APPEND sources ${source})
    endforeach()

    set(base ${CMAKE_CURRENT_BINARY_DIR}/${NAME})
    add_custom_command(
        OUTPUT ${base}.elf ${base}.hex ${base}.dis
        COMMAND ${RISCV_GCC_BIN} -march=${P_ARCH} -mabi=${P_ABI} -nostdlib -nostartfiles
                ${P_FLAGS} ${P_LINK_FLAGS} -o ${base}.elf ${sources}
        COMMAND ${RISCV_OBJCOPY_BIN} -O verilog ${base}.elf ${base}.hex
        COMMAND ${RISCV_OBJDUMP_BIN} -d ${base}.elf > ${base}.dis
        DEPENDS ${sources}
        COMMENT "RISC-V: building ${NAME}.hex"
        VERBATIM
    )
    add_custom_target(${NAME}.riscv ALL DEPENDS ${base}.hex)
endfunction()
