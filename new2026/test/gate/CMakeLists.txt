set(GATE ${DARK_CIRCUIT_RTL_LIB}/gate)
set(CELL ${DARK_CIRCUIT_RTL_LIB}/cell)

dc_add_icarus_test(gate_generic      TOP TbGate TB tb_gate.sv FLISTS ${GATE}/generic/gate_generic.flist)
dc_add_icarus_test(gate_cell_generic TOP TbGate TB tb_gate.sv FLISTS ${GATE}/cell/gate_cell.flist ${CELL}/generic/cell_generic.flist)
dc_add_icarus_test(gate_cell_cmos    TOP TbGate TB tb_gate.sv FLISTS ${GATE}/cell/gate_cell.flist ${CELL}/cmos/cell_cmos.flist)
dc_add_icarus_test(gate_cell_builtin TOP TbGate TB tb_gate.sv FLISTS ${GATE}/cell/gate_cell.flist ${CELL}/builtin/cell_builtin.flist)
dc_add_icarus_test(gate_cell_tsmc    TOP TbGate TB tb_gate.sv FLISTS ${GATE}/cell/gate_cell.flist ${CELL}/tsmc/cell_tsmc.flist
                   DEFINES DARK_CIRCUIT_FAKE_TSMC)
