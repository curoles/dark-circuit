add_subdirectory(plic_pkg)
add_subdirectory(plic_gateway)
add_subdirectory(plic_target)
add_subdirectory(plic_claim)
add_subdirectory(plic_decode)

set(LIB ${DARK_CIRCUIT_RTL_LIB})

# The whole PLIC, the same testbench with both libraries (the top's And gates come from the
# generic gates in both), on Verilator only: hundreds of register requests take long on
# event-driven Icarus; the parts' tests run on both.
dc_add_verilator_test(block_plic_behave TOP TbPlic TB tb_plic.sv
                      FLISTS ${LIB}/sim/sim.flist
                             ${LIB}/gate/generic/gate_generic.flist
                             ${LIB}/block/block_behave.flist)
dc_add_verilator_test(block_plic_struct TOP TbPlic TB tb_plic.sv
                      FLISTS ${LIB}/sim/sim.flist
                             ${LIB}/gate/generic/gate_generic.flist
                             ${LIB}/part/part.flist
                             ${LIB}/block/block_struct.flist)
