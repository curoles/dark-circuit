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
# Every source is compiled into <name>.objs/<n>_<source>.o with a dependency file
# (gcc -MD), so the program is rebuilt when a source or a header it includes changes;
# a linker script given as -T <file> in LINK_FLAGS is a dependency of the link.
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

    set(base ${CMAKE_CURRENT_BINARY_DIR}/${NAME})
    set(arch -march=${P_ARCH} -mabi=${P_ABI})

    # Compile every source with its dependency file; object names start with
    # the source number, so sources with the same name in different directories
    # do not collide.
    file(MAKE_DIRECTORY ${base}.objs)
    set(objs)
    set(n 0)
    foreach(source IN LISTS P_SOURCES)
        get_filename_component(source ${source} ABSOLUTE)
        get_filename_component(source_name ${source} NAME)
        set(obj ${base}.objs/${n}_${source_name}.o)
        add_custom_command(
            OUTPUT ${obj}
            COMMAND ${RISCV_GCC_BIN} ${arch} ${P_FLAGS} -MD -MF ${obj}.d -c -o ${obj} ${source}
            DEPENDS ${source}
            DEPFILE ${obj}.d
            COMMENT "RISC-V: compiling ${source_name} of ${NAME}"
            VERBATIM
        )
        list(APPEND objs ${obj})
        math(EXPR n "${n} + 1")
    endforeach()

    # Linker scripts given as "-T <file>" or "-T<file>".
    set(link_deps)
    set(next_is_script FALSE)
    foreach(flag IN LISTS P_LINK_FLAGS)
        if(next_is_script)
            get_filename_component(script ${flag} ABSOLUTE)
            list(APPEND link_deps ${script})
            set(next_is_script FALSE)
        elseif(flag STREQUAL "-T")
            set(next_is_script TRUE)
        elseif(flag MATCHES "^-T(.+)$" AND NOT flag MATCHES "^-Ttext|^-Tdata|^-Tbss")
            get_filename_component(script ${CMAKE_MATCH_1} ABSOLUTE)
            list(APPEND link_deps ${script})
        endif()
    endforeach()

    add_custom_command(
        OUTPUT ${base}.elf ${base}.hex ${base}.dis
        COMMAND ${RISCV_GCC_BIN} ${arch} -nostdlib -nostartfiles ${P_LINK_FLAGS} -o ${base}.elf ${objs}
        COMMAND ${RISCV_OBJCOPY_BIN} -O verilog ${base}.elf ${base}.hex
        COMMAND ${RISCV_OBJDUMP_BIN} -d ${base}.elf > ${base}.dis
        DEPENDS ${objs} ${link_deps}
        COMMENT "RISC-V: linking ${NAME}.elf, making ${NAME}.hex"
        VERBATIM
    )
    add_custom_target(${NAME}.riscv ALL DEPENDS ${base}.hex)
endfunction()
