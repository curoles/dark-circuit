set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions, built with the aggregate flists (sim: DcTestPkg).
dc_add_mainsim_test(block_arg_max_tree_behave TOP TbArgMaxTree TB tb_arg_max_tree.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
dc_add_mainsim_test(block_arg_max_tree_struct TOP TbArgMaxTree TB tb_arg_max_tree.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/block/block_struct.flist)
