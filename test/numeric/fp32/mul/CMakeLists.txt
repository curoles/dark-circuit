set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Behavioral only: the fp32 multipliers have no struct version. Their own flist: they
# are not in numeric_behave.flist, which designs read.
dc_add_mainsim_test(numeric_fp32_mul TOP TbFp32Mul TB tb_fp32_mul.sv
                    FLISTS ${LIB}/numeric/fp32/fp32.flist)
