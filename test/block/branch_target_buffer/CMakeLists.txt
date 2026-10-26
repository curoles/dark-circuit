set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Behave version only (no struct version yet).
dc_add_mainsim_test(block_branch_target_buffer_behave TOP TbBranchTargetBuffer
                    TB tb_branch_target_buffer.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
