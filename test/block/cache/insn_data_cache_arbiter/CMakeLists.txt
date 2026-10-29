set(LIB ${DARK_CIRCUIT_RTL_LIB})

# The behave version; the struct version comes next, against the same testbench.
dc_add_mainsim_test(block_insn_data_cache_arbiter_behave TOP TbInsnDataCacheArbiter
                    TB tb_insn_data_cache_arbiter.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
