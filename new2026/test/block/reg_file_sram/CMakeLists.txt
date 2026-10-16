set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions of Sram1R1W, built with the aggregate flists.
dc_add_mainsim_test(block_reg_file_sram_behave TOP TbRegFileSram TB tb_reg_file_sram.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
dc_add_mainsim_test(block_reg_file_sram_struct TOP TbRegFileSram TB tb_reg_file_sram.sv
                    FLISTS ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/sim/sim.flist
                           ${LIB}/block/block_struct.flist)
