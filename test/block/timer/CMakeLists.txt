set(LIB ${DARK_CIRCUIT_RTL_LIB})

# The same testbench with both libraries (the top's gates come from the generic gates in
# both).
dc_add_mainsim_test(block_timer_behave TOP TbTimer TB tb_timer.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/block/block_behave.flist)
dc_add_mainsim_test(block_timer_struct TOP TbTimer TB tb_timer.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/block/block_struct.flist)
