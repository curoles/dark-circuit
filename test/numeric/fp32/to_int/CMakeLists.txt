# Against TestFloat (cmake/testfloat.cmake): f32_to_i32 and f32_to_ui32, all their level-1
# cases (600 a mode) in the five rounding modes, -exact (NX on an inexact result); both
# invalid rules in one test; FP32_FLISTS: test/numeric/CMakeLists.txt.
dc_testfloat()
if(DARK_CIRCUIT_TESTFLOAT AND DARK_CIRCUIT_MAINSIM)
    dc_add_mainsim_test(numeric_fp32_to_int TOP TbFp32ToInt TB tb_fp32_to_int.sv
                        FLISTS ${FP32_FLISTS} ARGS +cases=${CMAKE_CURRENT_BINARY_DIR})
    foreach(f f32_to_i32 f32_to_ui32)
        dc_testfloat_cases(${CMAKE_CURRENT_BINARY_DIR}/${f} FUNCTION ${f} EXACT
                           FOR numeric_fp32_to_int.${DARK_CIRCUIT_MAINSIM})
    endforeach()
endif()
