set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Behave version only: the NoC blocks have no struct version yet.
dc_add_mainsim_test(block_noc_virt_ch_out_behave TOP TbNocVirtChOut
                    TB tb_noc_virt_ch_out.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
