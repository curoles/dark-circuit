set(SIM ${DARK_CIRCUIT_RTL_LIB}/sim)

foreach(sim IN ITEMS icarus verilator)
    cmake_language(CALL dc_add_${sim}_test sim_gen TOP TbSim    TB tb_sim.sv     FLISTS ${SIM}/sim.flist)
    cmake_language(CALL dc_add_${sim}_test sim_ram TOP TbSimRam TB tb_sim_ram.sv FLISTS ${SIM}/sim.flist)
    cmake_language(CALL dc_add_${sim}_test sim_rom TOP TbSimRom TB tb_sim_rom.sv FLISTS ${SIM}/sim.flist)
    cmake_language(CALL dc_add_${sim}_test sim_latency_ram TOP TbSimLatencyRAM TB tb_sim_latency_ram.sv
                   FLISTS ${SIM}/sim.flist)
endforeach()

# SimRAM load() of a program built by the RISC-V toolchain.
if(DARK_CIRCUIT_RISCV)
    dc_add_riscv_program(sim_ram_riscv SOURCES sim_ram_riscv.S
                         LINK_FLAGS -Wl,-Ttext=0 -Wl,--section-start=.tbdata=0x80)
    foreach(sim IN ITEMS icarus verilator)
        cmake_language(CALL dc_add_${sim}_test sim_ram_riscv TOP TbSimRamRiscv TB tb_sim_ram_riscv.sv
                       FLISTS ${SIM}/sim.flist ARGS +hex=${CMAKE_CURRENT_BINARY_DIR}/sim_ram_riscv.hex)
    endforeach()
endif()
