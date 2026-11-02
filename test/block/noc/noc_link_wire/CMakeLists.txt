set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions, built with the aggregate flists (NocLinkWire is one file
# of library blocks: DelayLine behave or struct).
dc_add_mainsim_test(block_noc_link_wire_behave TOP TbNocLinkWire
                    TB tb_noc_link_wire.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
dc_add_mainsim_test(block_noc_link_wire_struct TOP TbNocLinkWire
                    TB tb_noc_link_wire.sv
                    FLISTS ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/sim/sim.flist
                           ${LIB}/block/block_struct.flist)
