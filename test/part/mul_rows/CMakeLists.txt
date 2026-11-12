# MulRows: the sum of its rows against the product, W 8 exhaustive (every pair, all sign modes)
# at OUT 16 and 32, W 16 edge values and random operands at OUT 32.
dc_add_mainsim_test(part_mul_rows TOP TbMulRows TB tb_mul_rows.sv
                    FLISTS ${DARK_CIRCUIT_RTL_LIB}/gate/generic/gate_generic.flist
                           ${DARK_CIRCUIT_RTL_LIB}/part/part.flist)
