set(LIB ${DARK_CIRCUIT_RTL_LIB})

dc_add_mainsim_test(block_skewed_cache_behave TOP TbSkewedCache
                    TB tb_skewed_cache.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
