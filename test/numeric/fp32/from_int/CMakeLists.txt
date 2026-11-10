set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Against TestFloat (cmake/testfloat.cmake): i32_to_f32 and ui32_to_f32, all their level-1
# cases (372 a mode) in the five rounding modes, in one test. The hybrid blocks are built
# from the struct versions of the blocks they use, as in synthesis. The simulation depends
# on its case files, so building only its target (tools/mutate.py) makes them too.
dc_testfloat()
if(DARK_CIRCUIT_TESTFLOAT AND DARK_CIRCUIT_MAINSIM)
    dc_add_mainsim_test(numeric_fp32_from_int TOP TbFp32FromInt TB tb_fp32_from_int.sv
                        FLISTS ${LIB}/gate/generic/gate_generic.flist
                               ${LIB}/part/part.flist
                               ${LIB}/block/priority_encoder/struct/priority_encoder.flist
                               ${LIB}/block/barrel_shifter/struct/barrel_shifter.flist
                               ${LIB}/block/incr/struct/incr.flist
                               ${LIB}/numeric/fp32/fp32.flist
                        ARGS +cases=${CMAKE_CURRENT_BINARY_DIR})
    foreach(f i32 ui32)
        dc_testfloat_cases(${CMAKE_CURRENT_BINARY_DIR}/${f}_to_f32 FUNCTION ${f}_to_f32)
        add_dependencies(numeric_fp32_from_int.${DARK_CIRCUIT_MAINSIM}
                         testfloat_cases_${f}_to_f32)
    endforeach()
endif()
