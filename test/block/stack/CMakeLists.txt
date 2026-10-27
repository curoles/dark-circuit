set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Behave version only (no struct version yet).
dc_add_mainsim_test(block_stack_behave TOP TbStack TB tb_stack.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
