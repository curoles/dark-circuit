# Against TestFloat (cmake/testfloat.cmake): i32_to_f32 and ui32_to_f32, all their level-1
# cases (372 a mode) in the five rounding modes, in one test; FP32_FLISTS:
# test/numeric/CMakeLists.txt.
dc_testfloat()
if(DARK_CIRCUIT_TESTFLOAT AND DARK_CIRCUIT_MAINSIM)
    dc_add_mainsim_test(numeric_fp32_from_int TOP TbFp32FromInt TB tb_fp32_from_int.sv
                        FLISTS ${FP32_FLISTS} ARGS +cases=${CMAKE_CURRENT_BINARY_DIR})
    foreach(f i32 ui32)
        dc_testfloat_cases(${CMAKE_CURRENT_BINARY_DIR}/${f}_to_f32 FUNCTION ${f}_to_f32
                           FOR numeric_fp32_from_int.${DARK_CIRCUIT_MAINSIM})
    endforeach()
endif()
