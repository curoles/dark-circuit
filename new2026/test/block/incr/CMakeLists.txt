set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions, built with the aggregate flists.
dc_add_mainsim_test(block_incr_behave TOP TbIncr TB tb_incr.sv
                    FLISTS ${LIB}/block/block_behave.flist)
dc_add_mainsim_test(block_incr_struct TOP TbIncr TB tb_incr.sv
                    FLISTS ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/block/block_struct.flist)
