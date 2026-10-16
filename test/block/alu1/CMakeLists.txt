set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions, built with the aggregate flists.
dc_add_mainsim_test(block_alu1_behave TOP TbAlu1 TB tb_alu1.sv
                    FLISTS ${LIB}/block/block_behave.flist)
dc_add_mainsim_test(block_alu1_struct TOP TbAlu1 TB tb_alu1.sv
                    FLISTS ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/block/block_struct.flist)
