set(LIB ${DARK_CIRCUIT_RTL_LIB})

# The teaching multipliers (behavioral only, no struct version), with their own flist:
# they are in neither fp32.flist nor numeric_behave.flist, which designs read.
dc_add_mainsim_test(numeric_fp32_mul_teaching TOP TbFp32Mul TB tb_fp32_mul.sv
                    FLISTS ${LIB}/numeric/fp32/mul_teaching/mul_teaching.flist)
