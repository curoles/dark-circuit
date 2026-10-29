set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions, built with the aggregate flists.
dc_add_mainsim_test(block_insn_data_cache_arbiter_behave TOP TbInsnDataCacheArbiter
                    TB tb_insn_data_cache_arbiter.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
dc_add_mainsim_test(block_insn_data_cache_arbiter_struct TOP TbInsnDataCacheArbiter
                    TB tb_insn_data_cache_arbiter.sv
                    FLISTS ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/sim/sim.flist
                           ${LIB}/block/block_struct.flist)
