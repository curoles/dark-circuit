set(LIB ${DARK_CIRCUIT_RTL_LIB})

# The same testbench with both libraries (DmaEngine is wiring of the library's parts; the
# gates come from the generic gates in both).
dc_add_mainsim_test(block_dma_engine_behave TOP TbDmaEngine TB tb_dma_engine.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/block/block_behave.flist)
dc_add_mainsim_test(block_dma_engine_struct TOP TbDmaEngine TB tb_dma_engine.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/block/block_struct.flist)
