set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions, built with the aggregate flists.
dc_add_mainsim_test(block_pop_count_behave TOP TbPopCount TB tb_pop_count.sv
                    FLISTS ${LIB}/block/block_behave.flist)
dc_add_mainsim_test(block_pop_count_struct TOP TbPopCount TB tb_pop_count.sv
                    FLISTS ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/block/block_struct.flist)
