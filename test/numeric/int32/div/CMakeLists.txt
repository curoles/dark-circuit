set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions, built with the aggregate flists; Int32Div uses the
# Divider block (until their struct versions exist, the struct flists have behave ones).
dc_add_mainsim_test(numeric_int32_div_behave TOP TbInt32Div TB tb_int32_div.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist
                           ${LIB}/numeric/numeric_behave.flist)
dc_add_mainsim_test(numeric_int32_div_struct TOP TbInt32Div TB tb_int32_div.sv
                    FLISTS ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/sim/sim.flist
                           ${LIB}/block/block_struct.flist
                           ${LIB}/numeric/numeric_struct.flist)
