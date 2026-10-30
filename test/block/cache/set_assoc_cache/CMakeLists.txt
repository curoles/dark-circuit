set(LIB ${DARK_CIRCUIT_RTL_LIB})

dc_add_mainsim_test(block_set_assoc_cache_behave TOP TbSetAssocCache
                    TB tb_set_assoc_cache.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
