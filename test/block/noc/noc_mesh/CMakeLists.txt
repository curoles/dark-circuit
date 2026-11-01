set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Behave version only: the NoC blocks have no struct version yet.
dc_add_mainsim_test(block_noc_mesh_behave TOP TbNocMesh
                    TB tb_noc_mesh.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
