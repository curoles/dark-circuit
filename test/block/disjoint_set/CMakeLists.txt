set(LIB ${DARK_CIRCUIT_RTL_LIB})

# The behave version (no struct version yet), through its typed wrapper DisjointSetT.
dc_add_mainsim_test(block_disjoint_set_behave TOP TbDisjointSet TB tb_disjoint_set.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
