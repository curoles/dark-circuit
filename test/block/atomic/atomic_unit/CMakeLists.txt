set(LIB ${DARK_CIRCUIT_RTL_LIB})

# The behave version for now (the struct version comes next, against the same test).
dc_add_mainsim_test(block_atomic_unit_behave TOP TbAtomicUnit TB tb_atomic_unit.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
