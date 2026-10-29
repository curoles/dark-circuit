set(LIB ${DARK_CIRCUIT_RTL_LIB})

# The behave version; the struct version comes next, against the same testbench.
dc_add_mainsim_test(block_alu2_behave TOP TbAlu2 TB tb_alu2.sv
                    FLISTS ${LIB}/block/block_behave.flist)
