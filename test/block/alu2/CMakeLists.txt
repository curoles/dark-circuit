set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions, built with the aggregate flists.
dc_add_mainsim_test(block_alu2_behave TOP TbAlu2 TB tb_alu2.sv
                    FLISTS ${LIB}/block/block_behave.flist)
dc_add_mainsim_test(block_alu2_struct TOP TbAlu2 TB tb_alu2.sv
                    FLISTS ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/block/block_struct.flist)
