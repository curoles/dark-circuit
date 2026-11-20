set(LIB ${DARK_CIRCUIT_RTL_LIB})

# ExclusiveMonitor, behavioral only for now (a struct version later, as the library's other
# blocks); the aggregate flists (sim: DcTestPkg, the clock and reset generators).
dc_add_mainsim_test(block_exclusive_monitor_behave TOP TbExclusiveMonitor
                    TB tb_exclusive_monitor.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
