set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions, built with the aggregate flists.
dc_add_mainsim_test(block_prg_counter_behave TOP TbPrgCounter TB tb_prg_counter.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
dc_add_mainsim_test(block_prg_counter_struct TOP TbPrgCounter TB tb_prg_counter.sv
                    FLISTS ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/sim/sim.flist
                           ${LIB}/block/block_struct.flist)
