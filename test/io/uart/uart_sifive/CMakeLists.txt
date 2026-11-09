add_subdirectory(uart_sifive_regs)

set(LIB ${DARK_CIRCUIT_RTL_LIB})

# The device end to end, the same testbench with both libraries: software on the register
# port, the lines into SimUartRx and from SimUartTx.
dc_add_mainsim_test(io_uart_sifive_behave TOP TbUartSifive TB tb_uart_sifive.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/block/block_behave.flist
                           ${LIB}/io/io_behave.flist)
dc_add_mainsim_test(io_uart_sifive_struct TOP TbUartSifive TB tb_uart_sifive.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/block/block_struct.flist
                           ${LIB}/io/io_struct.flist)
