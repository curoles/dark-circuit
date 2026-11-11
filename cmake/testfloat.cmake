# @brief Berkeley TestFloat: IEEE 754 test cases for the floating-point blocks of the library.
#
# SoftFloat 3 and TestFloat 3 (John R. Hauser, BSD license) are fetched at configure time
# (fetch.cmake) and built at build time by their own Makefiles, in their fetched trees in the
# build directory: SoftFloat with its RISC-V specialization (a NaN result is the canonical
# NaN 0x7fc00000, no payload passes through: what RISC-V and the library's blocks give),
# then TestFloat's case generator testfloat_gen on it. A test reads case files that
# testfloat_gen writes at build time (dc_testfloat_cases). Why: kb rtl/lib/numeric/fp32/design.

# dc_softfloat()
#
# Fetch SoftFloat (once): its sources, for TestFloat and for the soft-float runtime of
# RISC-V programs (dc_softfloat_rv32). A macro: it sets DARK_CIRCUIT_SOFTFLOAT and
# SOFTFLOAT_DIR where it is called.
macro(dc_softfloat)
    dc_fetch_source(SOFTFLOAT
        GIT_REPOSITORY https://github.com/ucb-bar/berkeley-softfloat-3.git
        GIT_TAG        07ebd29db0cfb55723a79fbbffe99103ef38e305)
endmacro()

# dc_softfloat_rv32(<sources-var> <flags-var>)
#
# The sources of the soft-float runtime of RISC-V programs: sw/riscv/softfloat/soft_float.c
# and the single-precision part of SoftFloat with its RISC-V specialization, and the
# compiler flags they need (sw/riscv/softfloat/platform.h, SoftFloat's headers); after
# dc_softfloat().
function(dc_softfloat_rv32 SOURCES FLAGS)
    set(s ${SOFTFLOAT_DIR}/source)
    set(files softfloat_state.c RISCV/softfloat_raiseFlags.c RISCV/s_propagateNaNF32UI.c
              s_countLeadingZeros8.c s_countLeadingZeros32.c s_countLeadingZeros64.c
              s_shiftRightJam32.c s_shiftRightJam64.c s_shortShiftRightJam64.c
              s_normSubnormalF32Sig.c s_roundPackToF32.c s_normRoundPackToF32.c
              s_addMagsF32.c s_subMagsF32.c s_mulAddF32.c s_approxRecip_1Ks.c
              s_approxRecip32_1.c s_approxRecipSqrt_1Ks.c s_approxRecipSqrt32_1.c
              s_roundToI32.c s_roundToUI32.c f32_add.c f32_sub.c f32_mul.c f32_div.c
              f32_sqrt.c f32_mulAdd.c f32_eq.c f32_le.c f32_lt.c f32_lt_quiet.c
              f32_isSignalingNaN.c f32_to_i32_r_minMag.c f32_to_ui32_r_minMag.c
              i32_to_f32.c ui32_to_f32.c)
    list(TRANSFORM files PREPEND ${s}/)
    set(${SOURCES} ${PROJECT_SOURCE_DIR}/sw/riscv/softfloat/soft_float.c ${files}
        PARENT_SCOPE)
    set(${FLAGS} -I${PROJECT_SOURCE_DIR}/sw/riscv/softfloat -I${s}/include -I${s}/RISCV
        PARENT_SCOPE)
endfunction()

# dc_testfloat()
#
# Fetch SoftFloat and TestFloat and add target testfloat_gen (once); for the tests that use
# them, so other build trees do not fetch. A macro: it sets DARK_CIRCUIT_TESTFLOAT (both
# fetched, make found) and TESTFLOAT_GEN (the program) where it is called.
macro(dc_testfloat)
    dc_softfloat()
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

# The sampler of dc_testfloat_cases.
set(DC_TESTFLOAT_SAMPLE ${CMAKE_CURRENT_LIST_DIR}/testfloat_sample.awk)

# dc_testfloat_cases(<prefix> FUNCTION <function> [EVERY <k>] [SPECIAL <n>] [EXACT]
#                    [FOR <target>...])
#
# At build time, write the case files <prefix>.rne, .rtz, .rdn, .rup and .rmm: TestFloat's
# level-1 cases of <function> (i32_to_f32, f32_add, f32_mulAdd, ...) in each rounding mode,
# tininess after rounding (RISC-V). Level 1 is testfloat_gen's smallest set: 372 cases for
# i32_to_f32, 46464 for f32_add, over 6 million for f32_mulAdd, so a test keeps about one in
# k of them (EVERY, default 1: all), picked by a fixed pseudo-random generator
# (testfloat_sample.awk: the same files on every machine; every k-th line would alias with
# testfloat_gen's regular order and miss whole kinds of operands), and with SPECIAL every case
# with n or more special operands (zero, infinity, NaN: rare there, such as infinity times
# zero plus a NaN). A line per case: the operands, the result and the flags, in hex. FOR:
# each <target> (a test's simulation) depends on the files, so building only that target
# (tools/mutate.py) writes them too. EXACT: a conversion to an integer that is not exact
# flags inexact (testfloat_gen -exact; RISC-V's FCVT does, testfloat_gen does not by
# default).
function(dc_testfloat_cases PREFIX)
    cmake_parse_arguments(C "EXACT" "FUNCTION;EVERY;SPECIAL" "FOR" ${ARGN})
    if(NOT C_FUNCTION)
        message(FATAL_ERROR "dc_testfloat_cases(${PREFIX}): FUNCTION is required")
    endif()
    if(NOT C_EVERY)
        set(C_EVERY 1)
    endif()
    if(NOT C_SPECIAL)
        set(C_SPECIAL 0)
    endif()
    if(C_EXACT)
        set(exact -exact)
    else()
        set(exact -notexact)
    endif()
    # $1 testfloat_gen, $2 its mode, $3 the function, $4 k, $5 n, $6 the sampler, $7 the file,
    # $8 -exact or -notexact.
    set(script
        "\"$1\" $8 -r$2 -tininessafter $3 | awk -v k=$4 -v n=$5 -f \"$6\" > \"$7\"")
    set(files)
    foreach(pair rne:near_even rtz:minMag rdn:min rup:max rmm:near_maxMag)
        string(REPLACE ":" ";" pair ${pair})
        list(GET pair 0 suffix)
        list(GET pair 1 mode)
        set(file ${PREFIX}.${suffix})
        add_custom_command(OUTPUT ${file}
            COMMAND sh -c "${script}" sh ${TESTFLOAT_GEN} ${mode} ${C_FUNCTION} ${C_EVERY}
                    ${C_SPECIAL} ${DC_TESTFLOAT_SAMPLE} ${file} ${exact}
            DEPENDS testfloat_gen ${DC_TESTFLOAT_SAMPLE}
            COMMENT "TestFloat: ${C_FUNCTION}, round ${mode}"
            VERBATIM)
        list(APPEND files ${file})
    endforeach()
    # The target's name from the whole prefix: two tests may use one function.
    string(MAKE_C_IDENTIFIER "${PREFIX}" name)
    add_custom_target(testfloat_cases_${name} ALL DEPENDS ${files})
    foreach(target IN LISTS C_FOR)
        add_dependencies(${target} testfloat_cases_${name})
    endforeach()
endfunction()
