set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions, built with the aggregate flists.
dc_add_mainsim_test(block_noc_virt_ch_alloc_behave TOP TbNocVirtChAlloc
                    TB tb_noc_virt_ch_alloc.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
dc_add_mainsim_test(block_noc_virt_ch_alloc_struct TOP TbNocVirtChAlloc
                    TB tb_noc_virt_ch_alloc.sv
                    FLISTS ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/sim/sim.flist
                           ${LIB}/block/block_struct.flist)
