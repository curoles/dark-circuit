# Against TestFloat (cmake/testfloat.cmake), in the five rounding modes: f32_mulAdd (about one
# in 6000 of its 6.1 million level-1 cases, and all 1683 with three special operands, such as
# infinity times zero plus a NaN; each case as the four fused forms), f32_add, f32_sub and
# f32_mul (about one in 20 of 46464, and all 148 with two special operands); FP32_FLISTS:
# test/numeric/CMakeLists.txt. One test per STAGES (0: combinational, 1 to 3: streamed
# through the pipeline), the same case files.
dc_testfloat()
if(DARK_CIRCUIT_TESTFLOAT AND DARK_CIRCUIT_MAINSIM)
    set(sims)
    foreach(stages 0 1 2 3)
        if(stages EQUAL 0)
            set(test numeric_fp32_fma)
            set(limit)
        else()
            # Streamed: about 6000 operations a function keep the test near a second.
            set(test numeric_fp32_fma_stages${stages})
            set(limit +limit=6000)
        endif()
        dc_add_mainsim_test(${test} TOP TbFp32Fma TB tb_fp32_fma.sv
                            FLISTS ${FP32_FLISTS} DEFINES FMA_STAGES=${stages}
                            ARGS +cases=${CMAKE_CURRENT_BINARY_DIR} ${limit})
        list(APPEND sims ${test}.${DARK_CIRCUIT_MAINSIM})
    endforeach()
    dc_testfloat_cases(${CMAKE_CURRENT_BINARY_DIR}/f32_mulAdd FUNCTION f32_mulAdd EVERY 6000
                       SPECIAL 3 FOR ${sims})
    foreach(f f32_add f32_sub f32_mul)
        dc_testfloat_cases(${CMAKE_CURRENT_BINARY_DIR}/${f} FUNCTION ${f} EVERY 20 SPECIAL 2
                           FOR ${sims})
    endforeach()
endif()
