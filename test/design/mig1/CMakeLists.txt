set(SIM  ${DARK_CIRCUIT_RTL_LIB}/sim)
set(MIG1 ${DARK_CIRCUIT_RTL_DESIGN}/mig1)
set(SW   ${PROJECT_SOURCE_DIR}/sw/riscv)

# Programs need the RISC-V toolchain.
if(DARK_CIRCUIT_RISCV)
    # Mig1Cpu memories: load() of a program.
    dc_add_riscv_program(design_mig1_mem SOURCES mem.S LINK_FLAGS -T ${SW}/mig1.ld)
    foreach(sim IN ITEMS icarus verilator)
        cmake_language(CALL dc_add_${sim}_test design_mig1_mem TOP TbMig1Mem TB tb_mig1_mem.sv
                       FLISTS ${SIM}/sim.flist ${MIG1}/mig1.flist
                       ARGS +hex=${CMAKE_CURRENT_BINARY_DIR}/design_mig1_mem.hex)
    endforeach()
endif()
