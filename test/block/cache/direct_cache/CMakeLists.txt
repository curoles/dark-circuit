set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Behave version only (no struct version yet).
dc_add_mainsim_test(block_direct_cache_behave TOP TbDirectCache TB tb_direct_cache.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
