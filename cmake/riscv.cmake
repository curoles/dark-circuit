# @brief RISC-V programs for tests.
#
# Programs are built with the RISC-V GNU toolchain (gcc, objcopy, objdump, nm)
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
    unset(RISCV_NM_BIN CACHE)
    set(DC_RISCV_PREFIX_FOUND ${DARK_CIRCUIT_RISCV_PREFIX} CACHE INTERNAL "Prefix of found RISC-V programs")
endif()

dc_use_tool(RISCV RISCV_GCC=${DARK_CIRCUIT_RISCV_PREFIX}gcc
                  RISCV_OBJCOPY=${DARK_CIRCUIT_RISCV_PREFIX}objcopy
                  RISCV_OBJDUMP=${DARK_CIRCUIT_RISCV_PREFIX}objdump
                  RISCV_NM=${DARK_CIRCUIT_RISCV_PREFIX}nm)

# dc_riscv_probe(<out-var> <march> <instruction>)
#
# <out-var> is TRUE when the compiler assembles <instruction> with -march=<march>.
function(dc_riscv_probe OUT MARCH INSN)
    set(dir ${CMAKE_BINARY_DIR}/CMakeFiles/dc_riscv_probe)
    file(MAKE_DIRECTORY ${dir})
    file(WRITE ${dir}/probe.S "    ${INSN}\n")
    execute_process(COMMAND ${RISCV_GCC_BIN} -march=${MARCH} -mabi=ilp32 -c -o ${dir}/probe.o
                            ${dir}/probe.S
                    RESULT_VARIABLE result OUTPUT_QUIET ERROR_QUIET)
    if(result EQUAL 0)
        set(${OUT} TRUE PARENT_SCOPE)
    else()
        set(${OUT} FALSE PARENT_SCOPE)
    endif()
endfunction()

# What the compiler needs and knows, probed (not its version: any toolchain may be used).
# Since GCC 12 (ISA spec 20191213) the base ISA leaves out the CSR instructions and FENCE.I:
# they are the extensions Zicsr and Zifencei, which older compilers do not know by name; so
# every -march gets DC_RISCV_ARCH_SUFFIX. DARK_CIRCUIT_RISCV_ZBB: the compiler knows Zbb
# (tests of Zbb need it).
if(DARK_CIRCUIT_RISCV)
    dc_riscv_probe(base_has_csr rv32i "csrr a0, mscratch")
    if(base_has_csr)
        set(DC_RISCV_ARCH_SUFFIX "")
    else()
        set(DC_RISCV_ARCH_SUFFIX _zicsr_zifencei)
    endif()
    dc_riscv_probe(DARK_CIRCUIT_RISCV_ZBB rv32i${DC_RISCV_ARCH_SUFFIX}_zbb "clz a0, a1")
    execute_process(COMMAND ${RISCV_GCC_BIN} -dumpfullversion
                    OUTPUT_VARIABLE DC_RISCV_GCC_VERSION OUTPUT_STRIP_TRAILING_WHITESPACE
                    ERROR_QUIET)
    message(STATUS "RISC-V: gcc ${DC_RISCV_GCC_VERSION}, -march suffix "
                   "'${DC_RISCV_ARCH_SUFFIX}', Zbb ${DARK_CIRCUIT_RISCV_ZBB}")
endif()

# dc_riscv_cycle_ceiling(<out-var> <test> <version> <cycles> [<version> <cycles>]...)
#
# Cycle ceiling of a test of compiled C code, for the compiler in use: the <cycles> listed
# with its version (gcc -dumpfullversion). The cycles of C code change with the compiler
# (Dhrystone: gcc 12.2.0 4 % more than gcc 10.2.0, towers 12 % fewer), so a ceiling belongs
# to one compiler version. For a version not listed, <out-var> is a guard against a hang
# only, twice the largest ceiling, and a message says so: add the version and its cycles.
function(dc_riscv_cycle_ceiling OUT TEST)
    set(pairs ${ARGN})
    set(largest 0)
    while(pairs)
        list(POP_FRONT pairs version cycles)
        if(version STREQUAL DC_RISCV_GCC_VERSION)
            set(${OUT} ${cycles} PARENT_SCOPE)
            return()
        endif()
        if(cycles GREATER largest)
            set(largest ${cycles})
        endif()
    endwhile()
    math(EXPR guard "2 * ${largest}")
    message(STATUS "RISC-V: ${TEST}: no cycle ceiling for gcc ${DC_RISCV_GCC_VERSION}, "
                   "only a guard of ${guard} cycles")
    set(${OUT} ${guard} PARENT_SCOPE)
endfunction()

# dc_riscv_march(<out-var> <march>)
#
# <march> with DC_RISCV_ARCH_SUFFIX after its single-letter extensions, where the canonical
# order puts Zicsr and Zifencei: rv32im -> rv32im_zicsr_zifencei,
# rv32im_zbb -> rv32im_zicsr_zifencei_zbb.
function(dc_riscv_march OUT MARCH)
    string(FIND "${MARCH}" "_" underscore)
    if(underscore EQUAL -1)
        set(${OUT} "${MARCH}${DC_RISCV_ARCH_SUFFIX}" PARENT_SCOPE)
    else()
        string(SUBSTRING "${MARCH}" 0 ${underscore} letters)
        string(SUBSTRING "${MARCH}" ${underscore} -1 rest)
        set(${OUT} "${letters}${DC_RISCV_ARCH_SUFFIX}${rest}" PARENT_SCOPE)
    endif()
endfunction()

# dc_add_riscv_program(<name> SOURCES <file>...
#                      [ARCH <march>] [ABI <mabi>]
#                      [LINK_FLAGS <flag>...] [FLAGS <flag>...])
#
# Build bare-metal program <name>.elf from SOURCES in the current build directory,
# then <name>.hex (objcopy -O verilog: byte addresses and bytes, the format of
# SimRAM load()), <name>.dis (objdump -d) to read the code and <name>.sym (nm: address,
# type and name of every symbol, for testbenches that need an address).
#   ARCH       -march, default rv32i (with DC_RISCV_ARCH_SUFFIX, see dc_riscv_march)
#   ABI        -mabi, default ilp32
#   LINK_FLAGS link options, default -Wl,-Ttext=0 (code at address 0);
#              for example -T <linker script> to place code and data
#   FLAGS      more gcc options, for example -I<dir> or -D<macro>
# Every source is compiled into <name>.objs/<n>_<source>.o with a dependency file
# (gcc -MD), so the program is rebuilt when a source or a header it includes changes;
# a linker script given as -T <file> in LINK_FLAGS is a dependency of the link, and so are
# the options: a change of ARCH, ABI, LINK_FLAGS, FLAGS or of the toolchain rebuilds it.
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
    dc_riscv_march(march ${P_ARCH})
    set(arch -march=${march} -mabi=${P_ABI})

    # The command lines are a dependency too: the Makefile generator does not compare the
    # commands of custom commands. file(CONFIGURE) writes the file only when its content
    # changes, so it is newer than the objects only after a change of the options.
    file(MAKE_DIRECTORY ${base}.objs)
    set(options ${base}.objs/options.txt)
    file(CONFIGURE OUTPUT ${options}
         CONTENT "${RISCV_GCC_BIN} ${arch} ${P_FLAGS}\n${P_LINK_FLAGS}\n" @ONLY)

    # Compile every source with its dependency file; object names start with
    # the source number, so sources with the same name in different directories
    # do not collide.
    set(objs)
    set(n 0)
    foreach(source IN LISTS P_SOURCES)
        get_filename_component(source ${source} ABSOLUTE)
        get_filename_component(source_name ${source} NAME)
        set(obj ${base}.objs/${n}_${source_name}.o)
        add_custom_command(
            OUTPUT ${obj}
            COMMAND ${RISCV_GCC_BIN} ${arch} ${P_FLAGS} -MD -MF ${obj}.d -c -o ${obj} ${source}
            DEPENDS ${source} ${options}
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
        OUTPUT ${base}.elf ${base}.hex ${base}.dis ${base}.sym
        COMMAND ${RISCV_GCC_BIN} ${arch} -nostdlib -nostartfiles ${P_LINK_FLAGS} -o ${base}.elf ${objs}
        COMMAND ${RISCV_OBJCOPY_BIN} -O verilog ${base}.elf ${base}.hex
        COMMAND ${RISCV_OBJDUMP_BIN} -d ${base}.elf > ${base}.dis
        COMMAND ${RISCV_NM_BIN} ${base}.elf > ${base}.sym
        DEPENDS ${objs} ${link_deps} ${options}
        COMMENT "RISC-V: linking ${NAME}.elf, making ${NAME}.hex"
        VERBATIM
    )
    add_custom_target(${NAME}.riscv ALL DEPENDS ${base}.hex)
endfunction()
