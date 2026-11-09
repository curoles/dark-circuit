set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Gates only: the same in both libraries, one test.
dc_add_mainsim_test(io_uart_watermark TOP TbUartWatermark TB tb_uart_watermark.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/block/block_behave.flist
                           ${LIB}/io/io_behave.flist)
