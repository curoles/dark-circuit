set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Behave version only (no struct version yet).
dc_add_mainsim_test(block_gshare_branch_predictor_behave TOP TbGshareBranchPredictor
                    TB tb_gshare_branch_predictor.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
