set(LIB ${DARK_CIRCUIT_RTL_LIB})

# The behave version; the struct version comes next, against the same testbench.
dc_add_mainsim_test(block_compute_core_bitmanip_behave TOP TbComputeCoreBitmanip
                    TB tb_compute_core_bitmanip.sv
                    FLISTS ${LIB}/block/block_behave.flist)
