set(GATE ${DARK_CIRCUIT_RTL_LIB}/gate)
set(CELL ${DARK_CIRCUIT_RTL_LIB}/cell)

# Every simulator runs the testbenches with gate_generic.flist
# and with gate_cell.flist over cell flavors generic, builtin and tsmc.
foreach(sim IN ITEMS icarus verilator)
    cmake_language(CALL dc_add_${sim}_test gate_generic      TOP TbGate TB tb_gate.sv
                   FLISTS ${GATE}/generic/gate_generic.flist)
    cmake_language(CALL dc_add_${sim}_test gate_cell_generic TOP TbGate TB tb_gate.sv
                   FLISTS ${GATE}/cell/gate_cell.flist ${CELL}/generic/cell_generic.flist)
    cmake_language(CALL dc_add_${sim}_test gate_cell_builtin TOP TbGate TB tb_gate.sv
                   FLISTS ${GATE}/cell/gate_cell.flist ${CELL}/builtin/cell_builtin.flist)
    cmake_language(CALL dc_add_${sim}_test gate_cell_tsmc    TOP TbGate TB tb_gate.sv
                   FLISTS ${GATE}/cell/gate_cell.flist ${CELL}/tsmc/cell_tsmc.flist
                   DEFINES DARK_CIRCUIT_FAKE_TSMC)

    cmake_language(CALL dc_add_${sim}_test gate_seq_generic          TOP TbGateSeq TB tb_gate_seq.sv
                   FLISTS ${GATE}/generic/gate_generic.flist)
    cmake_language(CALL dc_add_${sim}_test gate_seq_cell_generic     TOP TbGateSeq TB tb_gate_seq.sv
                   FLISTS ${GATE}/cell/gate_cell.flist ${CELL}/generic/cell_generic.flist)
    cmake_language(CALL dc_add_${sim}_test gate_seq_cell_builtin     TOP TbGateSeq TB tb_gate_seq.sv
                   FLISTS ${GATE}/cell/gate_cell.flist ${CELL}/builtin/cell_builtin.flist)
    cmake_language(CALL dc_add_${sim}_test gate_seq_cell_builtin_udp TOP TbGateSeq TB tb_gate_seq.sv
                   FLISTS ${GATE}/cell/gate_cell.flist ${CELL}/builtin/cell_builtin.flist
                   DEFINES DARK_CIRCUIT_BUILTIN_UDP)
    cmake_language(CALL dc_add_${sim}_test gate_seq_cell_tsmc        TOP TbGateSeq TB tb_gate_seq.sv
                   FLISTS ${GATE}/cell/gate_cell.flist ${CELL}/tsmc/cell_tsmc.flist
                   DEFINES DARK_CIRCUIT_FAKE_TSMC)
endforeach()

# Cell flavor cmos models transistors, only 4-state simulator Icarus checks it:
# short circuit gives x, floating output gives z; 2-state Verilator does not see them.
dc_add_icarus_test(gate_cell_cmos     TOP TbGate    TB tb_gate.sv
                   FLISTS ${GATE}/cell/gate_cell.flist ${CELL}/cmos/cell_cmos.flist)
dc_add_icarus_test(gate_seq_cell_cmos TOP TbGateSeq TB tb_gate_seq.sv
                   FLISTS ${GATE}/cell/gate_cell.flist ${CELL}/cmos/cell_cmos.flist)
