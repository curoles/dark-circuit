set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions, built with the aggregate flists.
dc_add_mainsim_test(block_priority_encoder_behave TOP TbPriorityEncoder TB tb_priority_encoder.sv
                    FLISTS ${LIB}/block/block_behave.flist)
dc_add_mainsim_test(block_priority_encoder_struct TOP TbPriorityEncoder TB tb_priority_encoder.sv
                    FLISTS ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/block/block_struct.flist)
