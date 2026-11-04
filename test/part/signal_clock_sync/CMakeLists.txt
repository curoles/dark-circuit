dc_add_mainsim_test(part_signal_clock_sync TOP TbSignalClockSync TB tb_signal_clock_sync.sv
                    FLISTS ${DARK_CIRCUIT_RTL_LIB}/sim/sim.flist
                           ${DARK_CIRCUIT_RTL_LIB}/gate/generic/gate_generic.flist
                           ${DARK_CIRCUIT_RTL_LIB}/part/part.flist)
