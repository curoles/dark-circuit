# @brief RISC-V programs for tests.
#
# Programs are built with an LLVM toolchain (clang, its assembler, lld, llvm-objdump,
# llvm-nm) or a GNU one (gcc, its as and ld, objdump, nm), whichever is installed (both:
# LLVM), into Verilog hex files that SimRAM and SimROM load(), written by GNU objcopy
# -O verilog: the GNU toolchain's, or with LLVM the host's (it reads any little-endian ELF;
# LLVM's objcopy has no such format). Cache variables:
#   DARK_CIRCUIT_USE_RISCV          AUTO, ON or OFF, as for simulators
#   DARK_CIRCUIT_RISCV_TOOLCHAIN    AUTO (LLVM when found, else GNU), LLVM or GNU
#   DARK_CIRCUIT_RISCV_LLVM_SUFFIX  suffix of the LLVM programs (clang-23: -23); empty: the
#                                   newest clang-<n> found, else clang
#   DARK_CIRCUIT_RISCV_PREFIX       prefix of the GNU programs (riscv64-unknown-elf-, a path
#                                   too); empty: the first found of riscv64-unknown-elf-,
#                                   riscv32-unknown-elf-, riscv-none-elf- (xPack)
# What differs between the two toolchains is here only: clang's --target, lld's
# --image-base, the version that keys cycle ceilings (gcc-12.2.0, clang-23.1.6). Sources
# that the two assemble differently test __clang__ (clang defines it; GNU's gcc does not).

set(DARK_CIRCUIT_USE_RISCV AUTO CACHE STRING "Use RISCV: AUTO (if found), ON (required) or OFF")
set_property(CACHE DARK_CIRCUIT_USE_RISCV PROPERTY STRINGS AUTO ON OFF)
set(DARK_CIRCUIT_RISCV_TOOLCHAIN AUTO CACHE STRING
    "RISC-V toolchain: AUTO (LLVM when found, else GNU), LLVM or GNU")
set_property(CACHE DARK_CIRCUIT_RISCV_TOOLCHAIN PROPERTY STRINGS AUTO LLVM GNU)
set(DARK_CIRCUIT_RISCV_LLVM_SUFFIX "" CACHE STRING
    "Suffix of the LLVM programs (clang-23: -23); empty: the newest found")
set(DARK_CIRCUIT_RISCV_PREFIX "" CACHE STRING
    "Prefix of the GNU programs (riscv64-unknown-elf-, riscv-none-elf-, a path); empty: probe")

# Programs found with other settings are forgotten when the settings change.
set(dc_search "${DARK_CIRCUIT_RISCV_LLVM_SUFFIX}|${DARK_CIRCUIT_RISCV_PREFIX}")
if(NOT dc_search STREQUAL "${DC_RISCV_SEARCH}")
    foreach(var IN ITEMS RISCV_CLANG RISCV_LLD RISCV_LLVM_OBJDUMP RISCV_LLVM_NM RISCV_HOST_OBJCOPY
                         RISCV_GNU_GCC RISCV_GNU_OBJCOPY RISCV_GNU_OBJDUMP RISCV_GNU_NM)
        unset(${var}_BIN CACHE)
    endforeach()
    set(DC_RISCV_SEARCH "${dc_search}" CACHE INTERNAL "Settings of the found RISC-V programs")
endif()
unset(dc_search)

# @kb: cmake/riscv_toolchain
# dc_riscv_find_llvm(<out-var>)
#
# <out-var> is TRUE when clang and the LLVM programs with its suffix and a host objcopy are
# found (RISCV_CLANG_BIN, RISCV_LLD_BIN, RISCV_LLVM_OBJDUMP_BIN, RISCV_LLVM_NM_BIN,
# RISCV_HOST_OBJCOPY_BIN).
function(dc_riscv_find_llvm OUT)
    if(DARK_CIRCUIT_RISCV_LLVM_SUFFIX)
        set(names clang${DARK_CIRCUIT_RISCV_LLVM_SUFFIX})
    else()
        set(names)
        foreach(version RANGE 17 40)
            list(PREPEND names clang-${version})
        endforeach()
        list(APPEND names clang)
    endif()
    find_program(RISCV_CLANG_BIN NAMES ${names})
    if(NOT RISCV_CLANG_BIN)
        set(${OUT} FALSE PARENT_SCOPE)
        return()
    endif()
    get_filename_component(name ${RISCV_CLANG_BIN} NAME)
    string(REGEX REPLACE "^clang" "" suffix "${name}")
    find_program(RISCV_LLD_BIN ld.lld${suffix})
    find_program(RISCV_LLVM_OBJDUMP_BIN llvm-objdump${suffix})
    find_program(RISCV_LLVM_NM_BIN llvm-nm${suffix})
    find_program(RISCV_HOST_OBJCOPY_BIN objcopy)
    if(RISCV_LLD_BIN AND RISCV_LLVM_OBJDUMP_BIN AND RISCV_LLVM_NM_BIN AND RISCV_HOST_OBJCOPY_BIN)
        set(${OUT} TRUE PARENT_SCOPE)
    else()
        message(STATUS "RISCV: ${name} found, but not all of ld.lld${suffix}, "
                       "llvm-objdump${suffix}, llvm-nm${suffix}, objcopy")
        set(${OUT} FALSE PARENT_SCOPE)
    endif()
endfunction()

# dc_riscv_find_gnu(<out-var>)
#
# <out-var> is TRUE when gcc, objcopy, objdump and nm with one prefix are found
# (RISCV_GNU_GCC_BIN, RISCV_GNU_OBJCOPY_BIN, RISCV_GNU_OBJDUMP_BIN, RISCV_GNU_NM_BIN).
function(dc_riscv_find_gnu OUT)
    if(DARK_CIRCUIT_RISCV_PREFIX)
        set(names ${DARK_CIRCUIT_RISCV_PREFIX}gcc)
    else()
        set(names riscv64-unknown-elf-gcc riscv32-unknown-elf-gcc riscv-none-elf-gcc)
    endif()
    find_program(RISCV_GNU_GCC_BIN NAMES ${names})
    if(NOT RISCV_GNU_GCC_BIN)
        set(${OUT} FALSE PARENT_SCOPE)
        return()
    endif()
    string(REGEX REPLACE "gcc$" "" prefix "${RISCV_GNU_GCC_BIN}")
    find_program(RISCV_GNU_OBJCOPY_BIN ${prefix}objcopy)
    find_program(RISCV_GNU_OBJDUMP_BIN ${prefix}objdump)
    find_program(RISCV_GNU_NM_BIN ${prefix}nm)
    if(RISCV_GNU_OBJCOPY_BIN AND RISCV_GNU_OBJDUMP_BIN AND RISCV_GNU_NM_BIN)
        set(${OUT} TRUE PARENT_SCOPE)
    else()
        message(STATUS "RISCV: ${RISCV_GNU_GCC_BIN} found, but not all of its objcopy, "
                       "objdump, nm")
        set(${OUT} FALSE PARENT_SCOPE)
    endif()
endfunction()

# The toolchain: DC_RISCV_TOOLCHAIN (LLVM or GNU), RISCV_CC_BIN (clang or gcc),
# RISCV_OBJCOPY_BIN, RISCV_OBJDUMP_BIN, RISCV_NM_BIN, DC_RISCV_LINK_TOOL (LLVM: lld, its
# image base 0 so that code may start at address 0).
string(TOUPPER "${DARK_CIRCUIT_USE_RISCV}" dc_mode)
string(TOUPPER "${DARK_CIRCUIT_RISCV_TOOLCHAIN}" dc_want)
if(NOT dc_mode MATCHES "^(AUTO|ON|OFF)$")
    message(FATAL_ERROR "DARK_CIRCUIT_USE_RISCV=${DARK_CIRCUIT_USE_RISCV}, "
                        "expected AUTO, ON or OFF")
endif()
if(NOT dc_want MATCHES "^(AUTO|LLVM|GNU)$")
    message(FATAL_ERROR "DARK_CIRCUIT_RISCV_TOOLCHAIN=${DARK_CIRCUIT_RISCV_TOOLCHAIN}, "
                        "expected AUTO, LLVM or GNU")
endif()
set(DARK_CIRCUIT_RISCV FALSE)
set(DC_RISCV_TOOLCHAIN "")
if(dc_mode STREQUAL "OFF")
    message(STATUS "RISCV: disabled by DARK_CIRCUIT_USE_RISCV=OFF")
else()
    set(dc_llvm FALSE)
    set(dc_gnu FALSE)
    if(dc_want MATCHES "^(AUTO|LLVM)$")
        dc_riscv_find_llvm(dc_llvm)
    endif()
    if(dc_want STREQUAL "GNU" OR (dc_want STREQUAL "AUTO" AND NOT dc_llvm))
        dc_riscv_find_gnu(dc_gnu)
    endif()
    if(dc_llvm)
        set(DARK_CIRCUIT_RISCV TRUE)
        set(DC_RISCV_TOOLCHAIN LLVM)
        set(RISCV_CC_BIN ${RISCV_CLANG_BIN})
        set(RISCV_OBJCOPY_BIN ${RISCV_HOST_OBJCOPY_BIN})
        set(RISCV_OBJDUMP_BIN ${RISCV_LLVM_OBJDUMP_BIN})
        set(RISCV_NM_BIN ${RISCV_LLVM_NM_BIN})
        set(DC_RISCV_LINK_TOOL --ld-path=${RISCV_LLD_BIN} -Wl,--image-base=0)
    elseif(dc_gnu)
        set(DARK_CIRCUIT_RISCV TRUE)
        set(DC_RISCV_TOOLCHAIN GNU)
        set(RISCV_CC_BIN ${RISCV_GNU_GCC_BIN})
        set(RISCV_OBJCOPY_BIN ${RISCV_GNU_OBJCOPY_BIN})
        set(RISCV_OBJDUMP_BIN ${RISCV_GNU_OBJDUMP_BIN})
        set(RISCV_NM_BIN ${RISCV_GNU_NM_BIN})
        set(DC_RISCV_LINK_TOOL "")
    elseif(dc_mode STREQUAL "ON")
        message(FATAL_ERROR "RISCV: required by DARK_CIRCUIT_USE_RISCV=ON, but no "
                            "${dc_want} toolchain found")
    else()
        message(STATUS "RISCV: no ${dc_want} toolchain found, RISCV tests are disabled")
    endif()
    unset(dc_llvm)
    unset(dc_gnu)
endif()
unset(dc_mode)
unset(dc_want)

# dc_riscv_target(<out-var> <march>)
#
# The compiler's target options for <march>: with LLVM --target=riscv64-unknown-elf for
# rv64..., else --target=riscv32-unknown-elf; with GNU none (gcc has one target).
function(dc_riscv_target OUT MARCH)
    if(NOT DC_RISCV_TOOLCHAIN STREQUAL "LLVM")
        set(${OUT} "" PARENT_SCOPE)
    elseif(MARCH MATCHES "^rv64")
        set(${OUT} --target=riscv64-unknown-elf PARENT_SCOPE)
    else()
        set(${OUT} --target=riscv32-unknown-elf PARENT_SCOPE)
    endif()
endfunction()

# dc_riscv_probe(<out-var> <march> <instruction> [<flag>...])
#
# <out-var> is TRUE when the compiler assembles <instruction> with -march=<march> and the
# flags.
function(dc_riscv_probe OUT MARCH INSN)
    set(dir ${CMAKE_BINARY_DIR}/CMakeFiles/dc_riscv_probe)
    file(MAKE_DIRECTORY ${dir})
    file(WRITE ${dir}/probe.S "    ${INSN}\n")
    dc_riscv_target(target ${MARCH})
    execute_process(COMMAND ${RISCV_CC_BIN} ${target} -march=${MARCH} -mabi=ilp32 ${ARGN}
                            -c -o ${dir}/probe.o ${dir}/probe.S
                    RESULT_VARIABLE result OUTPUT_QUIET ERROR_QUIET)
    if(result EQUAL 0)
        set(${OUT} TRUE PARENT_SCOPE)
    else()
        set(${OUT} FALSE PARENT_SCOPE)
    endif()
endfunction()

# dc_riscv_probe_zfinx_c(<out-var> <march>)
#
# <out-var> is TRUE when the compiler makes Zfinx instructions from C float code with
# -march=<march> (clang does; gcc 12.2 assembles Zfinx but calls libgcc's soft-float
# functions for C floats).
function(dc_riscv_probe_zfinx_c OUT MARCH)
    set(dir ${CMAKE_BINARY_DIR}/CMakeFiles/dc_riscv_probe)
    file(MAKE_DIRECTORY ${dir})
    file(WRITE ${dir}/probe.c "float probe(float a, float b) { return a + b; }\n")
    dc_riscv_target(target ${MARCH})
    execute_process(COMMAND ${RISCV_CC_BIN} ${target} -march=${MARCH} -mabi=ilp32 -O2
                            -S -o ${dir}/probe.s ${dir}/probe.c
                    RESULT_VARIABLE result OUTPUT_QUIET ERROR_QUIET)
    set(${OUT} FALSE PARENT_SCOPE)
    if(result EQUAL 0)
        file(READ ${dir}/probe.s code)
        if(code MATCHES "fadd\\.s")
            set(${OUT} TRUE PARENT_SCOPE)
        endif()
    endif()
endfunction()

# dc_riscv_p_march(<march-var> <flags-var>)
#
# P (packed SIMD) as clang lists it (-print-supported-extensions): a ratified P is the
# -march part _p with no options; a draft is an experimental extension, named in -march
# with its version (clang-23: p 0.21, _p0p21) and enabled by
# -menable-experimental-extensions. Both empty when clang does not list P, and with GNU
# (gcc 12.2 has no P). The version comes from clang, not from here, so a newer clang is
# probed with its own and the P tests are not dropped without a word.
function(dc_riscv_p_march MARCH_OUT FLAGS_OUT)
    set(${MARCH_OUT} "" PARENT_SCOPE)
    set(${FLAGS_OUT} "" PARENT_SCOPE)
    if(NOT DC_RISCV_TOOLCHAIN STREQUAL "LLVM")
        return()
    endif()
    execute_process(COMMAND ${RISCV_CC_BIN} --target=riscv32-unknown-elf
                            -print-supported-extensions
                    OUTPUT_VARIABLE list ERROR_QUIET)
    # The list: the ratified extensions, then a heading and the experimental ones.
    string(FIND "${list}" "Experimental extensions" at)
    if(at EQUAL -1)
        set(ratified "${list}")
        set(experimental "")
    else()
        string(SUBSTRING "${list}" 0 ${at} ratified)
        string(SUBSTRING "${list}" ${at} -1 experimental)
    endif()
    set(line "\n[ \t]+p[ \t]+([0-9]+)\\.([0-9]+)[ \t]")   # "    p    0.21    'P' ..."
    if(ratified MATCHES "${line}")
        set(${MARCH_OUT} _p PARENT_SCOPE)
    elseif(experimental MATCHES "${line}")
        set(${MARCH_OUT} _p${CMAKE_MATCH_1}p${CMAKE_MATCH_2} PARENT_SCOPE)
        set(${FLAGS_OUT} -menable-experimental-extensions PARENT_SCOPE)
    endif()
endfunction()

# What the compiler needs and knows, probed (not its version: any toolchain may be used).
# Since the ISA spec 20191213 the base ISA leaves out the CSR instructions and FENCE.I:
# they are the extensions Zicsr and Zifencei, which older compilers do not know by name;
# when the compiler wants them named, every -march gets DC_RISCV_ARCH_SUFFIX.
# DARK_CIRCUIT_RISCV_ZBA, _ZBB: the compiler knows Zba, Zbb (their tests need it);
# DARK_CIRCUIT_RISCV_ZICBOM: it knows Zicbom (tests of the CBOs); DARK_CIRCUIT_RISCV_ZFINX:
# its assembler knows Zfinx (F on the x registers); DARK_CIRCUIT_RISCV_ZFINX_C: it makes
# Zfinx code from C (tests in C of the FPU need it); DARK_CIRCUIT_RISCV_P: it knows the
# draft P (packed SIMD) as the -march part DC_RISCV_P_MARCH with the options
# DC_RISCV_P_FLAGS (dc_riscv_p_march; clang-23: the experimental p 0.21), a warning when
# clang lists P but does not assemble it so. DC_RISCV_CC_VERSION: the compiler
# and its version, gcc-12.2.0 or clang-23.1.6 (dc_riscv_cycle_ceiling).
if(DARK_CIRCUIT_RISCV)
    dc_riscv_probe(base_has_csr rv32i "csrr a0, mscratch")
    if(base_has_csr)
        set(DC_RISCV_ARCH_SUFFIX "")
    else()
        set(DC_RISCV_ARCH_SUFFIX _zicsr_zifencei)
    endif()
    dc_riscv_probe(DARK_CIRCUIT_RISCV_ZBA rv32i${DC_RISCV_ARCH_SUFFIX}_zba "sh1add a0, a1, a2")
    dc_riscv_probe(DARK_CIRCUIT_RISCV_ZBB rv32i${DC_RISCV_ARCH_SUFFIX}_zbb "clz a0, a1")
    dc_riscv_probe(DARK_CIRCUIT_RISCV_ZICBOM rv32i${DC_RISCV_ARCH_SUFFIX}_zicbom
                   "cbo.inval (a0)")
    dc_riscv_probe(DARK_CIRCUIT_RISCV_ZFINX rv32i${DC_RISCV_ARCH_SUFFIX}_zfinx
                   "fadd.s a0, a1, a2")
    dc_riscv_probe_zfinx_c(DARK_CIRCUIT_RISCV_ZFINX_C rv32im${DC_RISCV_ARCH_SUFFIX}_zfinx)
    dc_riscv_p_march(DC_RISCV_P_MARCH DC_RISCV_P_FLAGS)
    set(DARK_CIRCUIT_RISCV_P FALSE)
    if(DC_RISCV_P_MARCH)
        dc_riscv_probe(DARK_CIRCUIT_RISCV_P rv32i${DC_RISCV_ARCH_SUFFIX}${DC_RISCV_P_MARCH}
                       "padd.b a0, a1, a2" ${DC_RISCV_P_FLAGS})
        if(NOT DARK_CIRCUIT_RISCV_P)
            message(WARNING "RISCV: ${RISCV_CC_BIN} lists P, but does not assemble padd.b "
                            "with -march=rv32i${DC_RISCV_P_MARCH} ${DC_RISCV_P_FLAGS}: "
                            "the P tests are not added")
        endif()
    endif()
    if(DC_RISCV_TOOLCHAIN STREQUAL "LLVM")
        execute_process(COMMAND ${RISCV_CC_BIN} -dumpversion OUTPUT_VARIABLE dc_version
                        OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
        set(DC_RISCV_CC_VERSION clang-${dc_version})
    else()
        execute_process(COMMAND ${RISCV_CC_BIN} -dumpfullversion OUTPUT_VARIABLE dc_version
                        OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
        set(DC_RISCV_CC_VERSION gcc-${dc_version})
    endif()
    unset(dc_version)
    message(STATUS "RISCV: ${DC_RISCV_TOOLCHAIN}, ${DC_RISCV_CC_VERSION} (${RISCV_CC_BIN}; "
                   "${RISCV_OBJCOPY_BIN}, ${RISCV_OBJDUMP_BIN}, ${RISCV_NM_BIN}), -march suffix "
                   "'${DC_RISCV_ARCH_SUFFIX}', Zba ${DARK_CIRCUIT_RISCV_ZBA}, "
                   "Zbb ${DARK_CIRCUIT_RISCV_ZBB}, "
                   "Zicbom ${DARK_CIRCUIT_RISCV_ZICBOM}, Zfinx ${DARK_CIRCUIT_RISCV_ZFINX}, "
                   "Zfinx from C ${DARK_CIRCUIT_RISCV_ZFINX_C}, "
                   "P ${DARK_CIRCUIT_RISCV_P} '${DC_RISCV_P_MARCH}'")
endif()

# dc_riscv_cycle_ceiling(<out-var> <test> <compiler-version> <cycles> [...]...)
#
# Cycle ceiling of a test of compiled C code, for the compiler in use: the <cycles> listed
# with its DC_RISCV_CC_VERSION (gcc-12.2.0, clang-23.1.6). The cycles of C code change with
# the compiler (Dhrystone: gcc 12.2.0 4 % more than gcc 10.2.0, towers 12 % fewer), so a
# ceiling belongs to one compiler version. For a version not listed, <out-var> is a guard
# against a hang only, twice the largest ceiling, and a message says so: add the version and
# its cycles.
function(dc_riscv_cycle_ceiling OUT TEST)
    set(pairs ${ARGN})
    set(largest 0)
    while(pairs)
        list(POP_FRONT pairs version cycles)
        if(version STREQUAL DC_RISCV_CC_VERSION)
            set(${OUT} ${cycles} PARENT_SCOPE)
            return()
        endif()
        if(cycles GREATER largest)
            set(largest ${cycles})
        endif()
    endwhile()
    math(EXPR guard "2 * ${largest}")
    message(STATUS "RISCV: ${TEST}: no cycle ceiling for ${DC_RISCV_CC_VERSION}, "
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
#                      [ALT_ARCH <march> ALT_SOURCES <file>...]
#                      [LINK_FLAGS <flag>...] [FLAGS <flag>...])
#
# Build bare-metal program <name>.elf from SOURCES in the current build directory,
# then <name>.hex (objcopy -O verilog: byte addresses and bytes, the format of
# SimRAM load()), <name>.dis (objdump -d) to read the code and <name>.sym (nm: address,
# type and name of every symbol, for testbenches that need an address).
#   ARCH       -march, default rv32i (with DC_RISCV_ARCH_SUFFIX, see dc_riscv_march)
#   ABI        -mabi, default ilp32
#   ALT_ARCH   -march of ALT_SOURCES (with the same ABI), for example a soft-float copy of
#              code beside one built for the FPU
#   LINK_FLAGS link options, default -Wl,-Ttext=0 (code at address 0);
#              for example -T <linker script> to place code and data
#   FLAGS      more compiler options, for example -I<dir> or -D<macro>
# Every source is compiled into <name>.objs/<n>_<source>.o with a dependency file (-MD),
# so the program is rebuilt when a source or a header it includes changes; a linker script
# given as -T <file> in LINK_FLAGS is a dependency of the link, and so are the options: a
# change of ARCH, ABI, LINK_FLAGS, FLAGS or of the toolchain rebuilds it.
# Does nothing if the RISC-V toolchain is not used.
function(dc_add_riscv_program NAME)
    if(NOT DARK_CIRCUIT_RISCV)
        return()
    endif()
    cmake_parse_arguments(P "" "ARCH;ABI;ALT_ARCH" "SOURCES;ALT_SOURCES;LINK_FLAGS;FLAGS"
                          ${ARGN})
    if(NOT P_SOURCES)
        message(FATAL_ERROR "RISC-V program ${NAME}: SOURCES are required")
    endif()
    if(P_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "RISC-V program ${NAME}: unknown arguments: ${P_UNPARSED_ARGUMENTS}")
    endif()
    if(P_ALT_SOURCES AND NOT P_ALT_ARCH)
        message(FATAL_ERROR "RISC-V program ${NAME}: ALT_SOURCES need ALT_ARCH")
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
    dc_riscv_target(target ${march})
    set(arch ${target} -march=${march} -mabi=${P_ABI})
    set(alt_arch)
    if(P_ALT_ARCH)
        dc_riscv_march(alt_march ${P_ALT_ARCH})
        dc_riscv_target(alt_target ${alt_march})
        set(alt_arch ${alt_target} -march=${alt_march} -mabi=${P_ABI})
    endif()

    # The command lines are a dependency too: the Makefile generator does not compare the
    # commands of custom commands. file(CONFIGURE) writes the file only when its content
    # changes, so it is newer than the objects only after a change of the options.
    file(MAKE_DIRECTORY ${base}.objs)
    set(options ${base}.objs/options.txt)
    set(content "${RISCV_CC_BIN} ${arch} ${P_FLAGS}\n${alt_arch}\n")
    string(APPEND content "${DC_RISCV_LINK_TOOL} ${P_LINK_FLAGS}\n")
    file(CONFIGURE OUTPUT ${options} CONTENT "${content}" @ONLY)

    # Compile every source with its dependency file (ALT_SOURCES with ALT_ARCH); object
    # names start with the source number, so sources with the same name in different
    # directories do not collide.
    set(objs)
    set(n 0)
    list(LENGTH P_SOURCES main_count)
    foreach(source IN LISTS P_SOURCES P_ALT_SOURCES)
        if(n LESS main_count)
            set(source_arch ${arch})
        else()
            set(source_arch ${alt_arch})
        endif()
        get_filename_component(source ${source} ABSOLUTE)
        get_filename_component(source_name ${source} NAME)
        set(obj ${base}.objs/${n}_${source_name}.o)
        add_custom_command(
            OUTPUT ${obj}
            COMMAND ${RISCV_CC_BIN} ${source_arch} ${P_FLAGS} -MD -MF ${obj}.d -c -o ${obj}
                    ${source}
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
        COMMAND ${RISCV_CC_BIN} ${arch} ${DC_RISCV_LINK_TOOL} -nostdlib -nostartfiles
                ${P_LINK_FLAGS} -o ${base}.elf ${objs}
        COMMAND ${RISCV_OBJCOPY_BIN} -O verilog ${base}.elf ${base}.hex
        COMMAND ${RISCV_OBJDUMP_BIN} -d ${base}.elf > ${base}.dis
        COMMAND ${RISCV_NM_BIN} ${base}.elf > ${base}.sym
        DEPENDS ${objs} ${link_deps} ${options}
        COMMENT "RISC-V: linking ${NAME}.elf, making ${NAME}.hex"
        VERBATIM
    )
    add_custom_target(${NAME}.riscv ALL DEPENDS ${base}.hex)
endfunction()
