set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions, built with the aggregate flists.
dc_add_mainsim_test(block_wallace_tree_behave TOP TbWallaceTree TB tb_wallace_tree.sv
                    FLISTS ${LIB}/block/block_behave.flist)
dc_add_mainsim_test(block_wallace_tree_struct TOP TbWallaceTree TB tb_wallace_tree.sv
                    FLISTS ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/block/block_struct.flist)
