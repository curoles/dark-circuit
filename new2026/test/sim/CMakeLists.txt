set(SIM ${DARK_CIRCUIT_RTL_LIB}/sim)

foreach(sim IN ITEMS icarus verilator)
    cmake_language(CALL dc_add_${sim}_test sim_gen TOP TbSim    TB tb_sim.sv     FLISTS ${SIM}/sim.flist)
    cmake_language(CALL dc_add_${sim}_test sim_ram TOP TbSimRam TB tb_sim_ram.sv FLISTS ${SIM}/sim.flist)
    cmake_language(CALL dc_add_${sim}_test sim_rom TOP TbSimRom TB tb_sim_rom.sv FLISTS ${SIM}/sim.flist)
endforeach()
