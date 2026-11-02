set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions, built with the aggregate flists.
dc_add_mainsim_test(block_noc_virt_ch_rtr_input_unit_behave TOP TbNocVirtChRtrInputUnit
                    TB tb_noc_virt_ch_rtr_input_unit.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
dc_add_mainsim_test(block_noc_virt_ch_rtr_input_unit_struct TOP TbNocVirtChRtrInputUnit
                    TB tb_noc_virt_ch_rtr_input_unit.sv
                    FLISTS ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/sim/sim.flist
                           ${LIB}/block/block_struct.flist)
