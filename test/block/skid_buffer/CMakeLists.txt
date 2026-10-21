set(LIB ${DARK_CIRCUIT_RTL_LIB})

# Same testbench for both versions, built with the aggregate flists. Verilator only:
# SkidBufferT, FifoVldRdyT and the source/sink have type parameters, which Icarus 11
# can not parse (DARK_CIRCUIT_ENABLE_MODULE_TYPE_PARAM).
dc_add_verilator_test(block_skid_buffer_behave TOP TbSkidBuffer TB tb_skid_buffer.sv
                      FLISTS ${LIB}/sim/sim.flist
                             ${LIB}/block/block_behave.flist)
dc_add_verilator_test(block_skid_buffer_struct TOP TbSkidBuffer TB tb_skid_buffer.sv
                      FLISTS ${LIB}/gate/generic/gate_generic.flist
                             ${LIB}/part/part.flist
                             ${LIB}/sim/sim.flist
                             ${LIB}/block/block_struct.flist)
