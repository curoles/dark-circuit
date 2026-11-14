set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions; QecPkg gives the surface code's matrices.
dc_add_mainsim_test(block_parity_check_behave TOP TbParityCheck TB tb_parity_check.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist
                           ${LIB}/qec/qec.flist)
dc_add_mainsim_test(block_parity_check_struct TOP TbParityCheck TB tb_parity_check.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/block/block_struct.flist
                           ${LIB}/qec/qec.flist)
