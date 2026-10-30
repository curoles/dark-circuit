set(LIB ${DARK_CIRCUIT_RTL_LIB})

# The behave version; the struct version comes next, against the same testbench.
dc_add_mainsim_test(block_skewed_cache_rd_only_behave TOP TbSkewedCacheRdOnly
                    TB tb_skewed_cache_rd_only.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)

# Miss rates of the skewed and the set-associative models on synthetic streams (the decision,
# kb skewed_cache_rd_only/compare): fails if skewed misses more where conflicts decide.
dc_add_mainsim_test(block_cache_compare TOP TbCacheCompare TB tb_cache_compare.sv
                    FLISTS ${LIB}/sim/sim.flist)
