# @brief Berkeley TestFloat: IEEE 754 test cases for the floating-point blocks of the library.
#
# SoftFloat 3 and TestFloat 3 (John R. Hauser, BSD license) are fetched at configure time
# (fetch.cmake) and built at build time by their own Makefiles, in their fetched trees in the
# build directory: SoftFloat with its RISC-V specialization (a NaN result is the canonical
# NaN 0x7fc00000, no payload passes through: what RISC-V and the library's blocks give),
# then TestFloat's case generator testfloat_gen on it. A test reads case files that
# testfloat_gen writes at build time (dc_testfloat_cases). Why: kb rtl/lib/numeric/fp32/design.

# dc_testfloat()
#
# Fetch SoftFloat and TestFloat and add target testfloat_gen (once); for the tests that use
# them, so other build trees do not fetch. A macro: it sets DARK_CIRCUIT_TESTFLOAT (both
# fetched, make found) and TESTFLOAT_GEN (the program) where it is called.
macro(dc_testfloat)
    dc_fetch_source(SOFTFLOAT
        GIT_REPOSITORY https://github.com/ucb-bar/berkeley-softfloat-3.git
        GIT_TAG        07ebd29db0cfb55723a79fbbffe99103ef38e305)
    dc_fetch_source(TESTFLOAT
        GIT_REPOSITORY https://github.com/ucb-bar/berkeley-testfloat-3.git
        GIT_TAG        a9c849f1b0eb0264b626d9686ffae167d996e3be)
    find_program(DC_MAKE make)
    if(NOT DARK_CIRCUIT_SOFTFLOAT OR NOT DC_MAKE)
        set(DARK_CIRCUIT_TESTFLOAT FALSE)
    endif()
    if(DARK_CIRCUIT_TESTFLOAT)
        set(TESTFLOAT_GEN ${TESTFLOAT_DIR}/build/Linux-x86_64-GCC/testfloat_gen)
        if(NOT TARGET testfloat_gen)
            add_custom_command(OUTPUT ${TESTFLOAT_GEN}
                COMMAND ${DC_MAKE} -s -C ${SOFTFLOAT_DIR}/build/Linux-x86_64-GCC
                        SPECIALIZE_TYPE=RISCV softfloat.a
                COMMAND ${DC_MAKE} -s -C ${TESTFLOAT_DIR}/build/Linux-x86_64-GCC
                        SOFTFLOAT_DIR=${SOFTFLOAT_DIR} testfloat_gen
                COMMENT "TestFloat: testfloat_gen on SoftFloat with the RISC-V specialization"
                VERBATIM)
            add_custom_target(testfloat_gen DEPENDS ${TESTFLOAT_GEN})
        endif()
    endif()
endmacro()

# dc_testfloat_cases(<prefix> FUNCTION <function> [EVERY <k>])
#
# At build time, write the case files <prefix>.rne, .rtz, .rdn, .rup and .rmm: TestFloat's
# level-1 cases of <function> (i32_to_f32, f32_add, f32_mulAdd, ...) in each rounding mode,
# tininess after rounding (RISC-V), every k-th of them (default 1: all). Level 1 is
# testfloat_gen's smallest set: 372 cases for i32_to_f32, 46464 for f32_add, over 6 million
# for f32_mulAdd; EVERY keeps a test at about a second, and the special operands that
# testfloat_gen spreads through its cases still come. A line per case: the operands, the
# result and the flags, in hex.
function(dc_testfloat_cases PREFIX)
    cmake_parse_arguments(C "" "FUNCTION;EVERY" "" ${ARGN})
    if(NOT C_FUNCTION)
        message(FATAL_ERROR "dc_testfloat_cases(${PREFIX}): FUNCTION is required")
    endif()
    if(NOT C_EVERY)
        set(C_EVERY 1)
    endif()
    # $1 testfloat_gen, $2 its mode, $3 the function, $4 k, $5 the file.
    set(script "\"$1\" -r$2 -tininessafter $3 | awk -v k=$4 '(NR - 1) % k == 0' > \"$5\"")
    set(files)
    foreach(pair rne:near_even rtz:minMag rdn:min rup:max rmm:near_maxMag)
        string(REPLACE ":" ";" pair ${pair})
        list(GET pair 0 suffix)
        list(GET pair 1 mode)
        set(file ${PREFIX}.${suffix})
        add_custom_command(OUTPUT ${file}
            COMMAND sh -c "${script}" sh ${TESTFLOAT_GEN} ${mode} ${C_FUNCTION} ${C_EVERY} ${file}
            DEPENDS testfloat_gen
            COMMENT "TestFloat: ${C_FUNCTION}, round ${mode}"
            VERBATIM)
        list(APPEND files ${file})
    endforeach()
    get_filename_component(name ${PREFIX} NAME)
    add_custom_target(testfloat_cases_${name} ALL DEPENDS ${files})
endfunction()
