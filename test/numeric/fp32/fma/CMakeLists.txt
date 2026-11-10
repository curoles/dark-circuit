# Against TestFloat (cmake/testfloat.cmake), in the five rounding modes: f32_mulAdd (about one
# in 6000 of its 6.1 million level-1 cases, and all 1683 with three special operands, such as
# infinity times zero plus a NaN; each case as the four fused forms), f32_add, f32_sub and
# f32_mul (about one in 20 of 46464, and all 148 with two special operands); FP32_FLISTS:
# test/numeric/CMakeLists.txt.
dc_testfloat()
if(DARK_CIRCUIT_TESTFLOAT AND DARK_CIRCUIT_MAINSIM)
    dc_add_mainsim_test(numeric_fp32_fma TOP TbFp32Fma TB tb_fp32_fma.sv
                        FLISTS ${FP32_FLISTS} ARGS +cases=${CMAKE_CURRENT_BINARY_DIR})
    set(sim numeric_fp32_fma.${DARK_CIRCUIT_MAINSIM})
    dc_testfloat_cases(${CMAKE_CURRENT_BINARY_DIR}/f32_mulAdd FUNCTION f32_mulAdd EVERY 6000
                       SPECIAL 3 FOR ${sim})
    foreach(f f32_add f32_sub f32_mul)
        dc_testfloat_cases(${CMAKE_CURRENT_BINARY_DIR}/${f} FUNCTION ${f} EVERY 20 SPECIAL 2
                           FOR ${sim})
    endforeach()
endif()
