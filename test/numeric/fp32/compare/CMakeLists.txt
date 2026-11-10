# Fp32Compare, Fp32MinMax, Fp32Class, Fp32SignInject on TestFloat's compare cases
# (cmake/testfloat.cmake): about one in 20 of each compare function's 46464 level-1 cases and
# all 148 with two special operands; a compare does not round, the test reads the RNE files
# only; FP32_FLISTS: test/numeric/CMakeLists.txt.
dc_testfloat()
if(DARK_CIRCUIT_TESTFLOAT AND DARK_CIRCUIT_MAINSIM)
    dc_add_mainsim_test(numeric_fp32_compare TOP TbFp32Compare TB tb_fp32_compare.sv
                        FLISTS ${FP32_FLISTS} ARGS +cases=${CMAKE_CURRENT_BINARY_DIR})
    foreach(f f32_eq f32_lt f32_le f32_eq_signaling f32_lt_quiet f32_le_quiet)
        dc_testfloat_cases(${CMAKE_CURRENT_BINARY_DIR}/${f} FUNCTION ${f} EVERY 20 SPECIAL 2
                           FOR numeric_fp32_compare.${DARK_CIRCUIT_MAINSIM})
    endforeach()
endif()
