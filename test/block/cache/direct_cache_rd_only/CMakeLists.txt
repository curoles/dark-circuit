set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Behave version only (no struct version yet).
dc_add_mainsim_test(block_direct_cache_rd_only_behave TOP TbDirectCacheRdOnly
                    TB tb_direct_cache_rd_only.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
