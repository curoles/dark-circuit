set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Behave flists (DelayLine behave); NocLinkWire itself is only library blocks.
dc_add_mainsim_test(block_noc_link_wire_behave TOP TbNocLinkWire
                    TB tb_noc_link_wire.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
