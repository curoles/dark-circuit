set(LIB ${DARK_CIRCUIT_RTL_LIB})

# The same testbench with both libraries (the module is wiring of the library's parts).
dc_add_mainsim_test(io_uart_sifive_regs_behave TOP TbUartSifiveRegs TB tb_uart_sifive_regs.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/block/block_behave.flist
                           ${LIB}/io/io_behave.flist)
dc_add_mainsim_test(io_uart_sifive_regs_struct TOP TbUartSifiveRegs TB tb_uart_sifive_regs.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/block/block_struct.flist
                           ${LIB}/io/io_struct.flist)
