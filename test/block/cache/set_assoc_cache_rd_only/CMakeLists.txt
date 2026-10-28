set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions, built with the aggregate flists.
dc_add_mainsim_test(block_set_assoc_cache_rd_only_behave TOP TbSetAssocCacheRdOnly
                    TB tb_set_assoc_cache_rd_only.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
dc_add_mainsim_test(block_set_assoc_cache_rd_only_struct TOP TbSetAssocCacheRdOnly
                    TB tb_set_assoc_cache_rd_only.sv
                    FLISTS ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/sim/sim.flist
                           ${LIB}/block/block_struct.flist)
