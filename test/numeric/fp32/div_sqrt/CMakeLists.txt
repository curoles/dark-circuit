# Against TestFloat (cmake/testfloat.cmake), in the five rounding modes: f32_div (about one in
# 20 of its 46464 level-1 cases, and all with two special operands) and f32_sqrt (all its
# level-1 cases); FP32_FLISTS: test/numeric/CMakeLists.txt.
dc_testfloat()
if(DARK_CIRCUIT_TESTFLOAT AND DARK_CIRCUIT_MAINSIM)
    dc_add_mainsim_test(numeric_fp32_div_sqrt TOP TbFp32DivSqrt TB tb_fp32_div_sqrt.sv
                        FLISTS ${FP32_FLISTS} ARGS +cases=${CMAKE_CURRENT_BINARY_DIR})
    set(sim numeric_fp32_div_sqrt.${DARK_CIRCUIT_MAINSIM})
    dc_testfloat_cases(${CMAKE_CURRENT_BINARY_DIR}/f32_div FUNCTION f32_div EVERY 20 SPECIAL 2
                       FOR ${sim})
    dc_testfloat_cases(${CMAKE_CURRENT_BINARY_DIR}/f32_sqrt FUNCTION f32_sqrt FOR ${sim})
endif()
