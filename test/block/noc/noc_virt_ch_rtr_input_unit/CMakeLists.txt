set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Behave version only: the NoC blocks have no struct version yet.
dc_add_mainsim_test(block_noc_virt_ch_rtr_input_unit_behave TOP TbNocVirtChRtrInputUnit
                    TB tb_noc_virt_ch_rtr_input_unit.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
