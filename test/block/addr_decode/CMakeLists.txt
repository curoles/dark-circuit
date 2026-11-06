set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions, built with the aggregate flists (sim: DcTestPkg).
dc_add_mainsim_test(block_addr_decode_behave TOP TbAddrDecode TB tb_addr_decode.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/block/block_behave.flist)
dc_add_mainsim_test(block_addr_decode_struct TOP TbAddrDecode TB tb_addr_decode.sv
                    FLISTS ${LIB}/sim/sim.flist
                           ${LIB}/gate/generic/gate_generic.flist
                           ${LIB}/part/part.flist
                           ${LIB}/block/block_struct.flist)
