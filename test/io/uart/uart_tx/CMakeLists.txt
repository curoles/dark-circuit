set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions, against the UART line models of sim.flist (SimUartTx,
# SimUartRx).
dc_add_mainsim_test(io_uart_tx_behave TOP TbUartTx TB tb_uart_tx.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/io/io_behave.flist)
dc_add_mainsim_test(io_uart_tx_struct TOP TbUartTx TB tb_uart_tx.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/block/block_struct.flist
                           ${LIB}/io/io_struct.flist)
