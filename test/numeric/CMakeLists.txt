add_subdirectory(int32/mul)
add_subdirectory(int32/div)
# The fp32 blocks (hybrid) with the struct versions of the blocks they use, as in
# synthesis.
set(FP32_FLISTS ${DARK_CIRCUIT_RTL_LIB}/gate/generic/gate_generic.flist
                ${DARK_CIRCUIT_RTL_LIB}/part/part.flist
                ${DARK_CIRCUIT_RTL_LIB}/block/priority_encoder/struct/priority_encoder.flist
                ${DARK_CIRCUIT_RTL_LIB}/block/barrel_shifter/struct/barrel_shifter.flist
                ${DARK_CIRCUIT_RTL_LIB}/block/incr/struct/incr.flist
                ${DARK_CIRCUIT_RTL_LIB}/block/wallace_tree/struct/wallace_tree.flist
                ${DARK_CIRCUIT_RTL_LIB}/block/delay_line/struct/delay_line.flist
                ${DARK_CIRCUIT_RTL_LIB}/numeric/fp32/fp32.flist)
add_subdirectory(fp32/mul_teaching)
add_subdirectory(fp32/from_int)
add_subdirectory(fp32/fma)
add_subdirectory(fp32/compare)
add_subdirectory(fp32/to_int)
add_subdirectory(fp32/div_sqrt)
# The packed SIMD blocks (hybrid) with the parts they use.
set(PACKED_FLISTS ${DARK_CIRCUIT_RTL_LIB}/gate/generic/gate_generic.flist
                  ${DARK_CIRCUIT_RTL_LIB}/part/part.flist
                  ${DARK_CIRCUIT_RTL_LIB}/numeric/packed/packed.flist)
add_subdirectory(packed/add)
