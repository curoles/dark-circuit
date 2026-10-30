set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions, built with the aggregate flists.
dc_add_mainsim_test(block_mux_n_behave TOP TbMuxN TB tb_mux_n.sv
                    FLISTS ${LIB}/block/block_behave.flist)
dc_add_mainsim_test(block_mux_n_struct TOP TbMuxN TB tb_mux_n.sv
                    FLISTS ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/block/block_struct.flist)
