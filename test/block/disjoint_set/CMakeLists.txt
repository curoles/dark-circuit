set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions, through the typed wrapper DisjointSetT.
dc_add_mainsim_test(block_disjoint_set_behave TOP TbDisjointSet TB tb_disjoint_set.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
dc_add_mainsim_test(block_disjoint_set_struct TOP TbDisjointSet TB tb_disjoint_set.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/block/block_struct.flist)
