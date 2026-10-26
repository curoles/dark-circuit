set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions, built with the aggregate flists.
dc_add_mainsim_test(block_gshare_branch_predictor_behave TOP TbGshareBranchPredictor
                    TB tb_gshare_branch_predictor.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
dc_add_mainsim_test(block_gshare_branch_predictor_struct TOP TbGshareBranchPredictor
                    TB tb_gshare_branch_predictor.sv
                    FLISTS ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/sim/sim.flist
                           ${LIB}/block/block_struct.flist)
