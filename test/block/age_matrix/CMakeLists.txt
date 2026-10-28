set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Behave version only (no struct version yet).
dc_add_mainsim_test(block_age_matrix_behave TOP TbAgeMatrix TB tb_age_matrix.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
