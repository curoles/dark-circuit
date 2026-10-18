set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions, built with the aggregate flists.
dc_add_mainsim_test(block_stochastic_bitstream_gen_behave TOP TbStochasticBitstreamGen
                    TB tb_stochastic_bitstream_gen.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
dc_add_mainsim_test(block_stochastic_bitstream_gen_struct TOP TbStochasticBitstreamGen
                    TB tb_stochastic_bitstream_gen.sv
                    FLISTS ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/sim/sim.flist
                           ${LIB}/block/block_struct.flist)
