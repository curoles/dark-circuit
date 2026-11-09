set(LIB ${DARK_CIRCUIT_RTL_LIB})

# The device end to end, the same testbench with both libraries (DmaSifive is wiring of the
# library's parts; the gates come from the generic gates in both).
dc_add_mainsim_test(block_dma_sifive_behave TOP TbDmaSifive TB tb_dma_sifive.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/block/block_behave.flist)
dc_add_mainsim_test(block_dma_sifive_struct TOP TbDmaSifive TB tb_dma_sifive.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/block/block_struct.flist)
