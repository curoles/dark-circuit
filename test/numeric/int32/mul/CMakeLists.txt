set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions, built with the aggregate flists; the struct version
# uses blocks (CsaMultiplier), parts and gates.
dc_add_mainsim_test(numeric_int32_mul_behave TOP TbInt32Mul TB tb_int32_mul.sv
                    FLISTS ${LIB}/numeric/numeric_behave.flist)
dc_add_mainsim_test(numeric_int32_mul_struct TOP TbInt32Mul TB tb_int32_mul.sv
                    FLISTS ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/block/block_struct.flist
                           ${LIB}/numeric/numeric_struct.flist)
