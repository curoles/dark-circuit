set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions.
dc_add_mainsim_test(qec_detection_events_behave TOP TbDetectionEvents TB tb_detection_events.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/qec/qec_behave.flist)
dc_add_mainsim_test(qec_detection_events_struct TOP TbDetectionEvents TB tb_detection_events.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/qec/qec_struct.flist)
