set(LIB ${DARK_CIRCUIT_RTL_LIB})

# The register map of PlicPkg (sim: DcTestPkg).
dc_add_mainsim_test(block_plic_pkg TOP TbPlicPkg TB tb_plic_pkg.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/plic/plic.flist)
