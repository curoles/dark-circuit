set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions, built with the aggregate flists.
dc_add_mainsim_test(block_decoder_behave TOP TbDecoder TB tb_decoder.sv
                    FLISTS ${LIB}/block/block_behave.flist)
dc_add_mainsim_test(block_decoder_struct TOP TbDecoder TB tb_decoder.sv
                    FLISTS ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/block/block_struct.flist)
