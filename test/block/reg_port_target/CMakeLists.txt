set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions, built with the aggregate flists (sim: DcTestPkg, the clock
# and reset generators).
dc_add_mainsim_test(block_reg_port_target_behave TOP TbRegPortTarget TB tb_reg_port_target.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
dc_add_mainsim_test(block_reg_port_target_struct TOP TbRegPortTarget TB tb_reg_port_target.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/block/block_struct.flist)
