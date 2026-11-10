set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Behavioral only: the fp32 multipliers have no struct version. Their own flist: they
# are not in numeric_behave.flist, which designs read. Gates, parts and blocks: the
# hybrid blocks in fp32.flist (Fp32Round, Fp32FromInt) use them.
dc_add_mainsim_test(numeric_fp32_mul TOP TbFp32Mul TB tb_fp32_mul.sv
                    FLISTS ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/block/priority_encoder/struct/priority_encoder.flist
                           ${LIB}/block/barrel_shifter/struct/barrel_shifter.flist
                           ${LIB}/block/incr/struct/incr.flist
                           ${LIB}/numeric/fp32/fp32.flist)
