set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Functions only: one test.
dc_add_mainsim_test(qec_pkg TOP TbQecPkg TB tb_qec_pkg.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/qec/qec.flist)
