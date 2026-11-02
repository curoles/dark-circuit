set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions. The struct version on Verilator only: thousands of
# gates take many seconds on event-driven Icarus even for a short run.
dc_add_mainsim_test(block_noc_virt_ch_router_behave TOP TbNocVirtChRouter
                    TB tb_noc_virt_ch_router.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
dc_add_verilator_test(block_noc_virt_ch_router_struct TOP TbNocVirtChRouter
                      TB tb_noc_virt_ch_router.sv
                      FLISTS ${LIB}/gate/generic/gate_generic.flist
                             ${LIB}/part/part.flist
                             ${LIB}/sim/sim.flist
                             ${LIB}/block/block_struct.flist)
