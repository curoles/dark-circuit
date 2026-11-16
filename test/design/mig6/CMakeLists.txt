set(LIB  ${DARK_CIRCUIT_RTL_LIB})
set(MIG6 ${DARK_CIRCUIT_RTL_DESIGN}/mig6)
set(SW   ${PROJECT_SOURCE_DIR}/sw/riscv)

# Mig6 is a prototype (rtl/design/mig6/README.md): its core (Mig6Core, a copy of Mig3's), the
# PE (Mig6Pe: the core and its local memory) and programs on the PEs of TbMig6.

# Files generated from cfg/mig6_config.yaml are up to date.
dc_add_config_check(design_mig6 CONFIG ${MIG6}/cfg/mig6_config.yaml)

# Hardware files of Mig6Core: struct versions of the library, built from generic gates, the
# fp32 and packed blocks (one version: hybrid), RISC-V formats and encodings.
set(SYNTH_FLISTS ${LIB}/gate/generic/gate_generic.flist ${LIB}/part/part.flist
                 ${LIB}/block/block_struct.flist ${LIB}/numeric/numeric_struct.flist
                 ${LIB}/numeric/fp32/fp32.flist ${LIB}/numeric/packed/packed.flist
                 ${LIB}/riscv/riscv.flist ${MIG6}/mig6.flist)

# Mig6Core converts to Verilog-2005 with sv2v and elaborates.
dc_add_sv2v_check(design_mig6 TOP Mig6Core FLISTS ${SYNTH_FLISTS})

# Synthesis of Mig6Core: build target design_mig6.synth (make mig6_synth), not a test. The
# tag and data RAMs of the caches are memory macros in a chip: black boxes.
dc_add_yosys_synth(design_mig6 TOP Mig6Core FLISTS ${SYNTH_FLISTS}
                   BLACKBOX_RAM_MODULES CacheTagRam CacheDataRam)

# Mig6 runs on the main simulator only, as Mig3 (see cmake/dark_circuit.cmake); programs need
# the RISC-V toolchain.
if(NOT DARK_CIRCUIT_MAINSIM OR NOT DARK_CIRCUIT_RISCV)
    message(STATUS "Mig6: no main simulator or no RISC-V toolchain, Mig6 programs are disabled")
    return()
endif()
set(SIM ${DARK_CIRCUIT_MAINSIM})

# Simulation of the PEs: behave versions of the library (fast to simulate).
set(FLISTS ${LIB}/sim/sim.flist ${LIB}/gate/generic/gate_generic.flist ${LIB}/part/part.flist
           ${LIB}/block/block_behave.flist ${LIB}/numeric/numeric_behave.flist
           ${LIB}/numeric/fp32/fp32.flist ${LIB}/numeric/packed/packed.flist
           ${LIB}/riscv/riscv.flist ${MIG6}/mig6.flist)
cmake_language(CALL dc_add_${SIM}_build design_mig6_sim TOP TbMig6 TB tb/tb_mig6.sv
               FLISTS ${FLISTS} ${CMAKE_CURRENT_SOURCE_DIR}/tb/tb_mig6.flist)

# mig6_program_test(<name> SOURCES <file>... [ARCH <march>] [FLAGS <flag>...] [ARGS <arg>...])
#
# A C program on every PE of TbMig6: crt0, semihosting and Mig6's exit (the hart's ID in a2,
# mig6_exit.c) with the program's SOURCES, linked by sw/riscv/mig6.ld; the test passes when
# every hart exits with 0 (TbMig6).
function(mig6_program_test NAME)
    cmake_parse_arguments(P "" "ARCH" "SOURCES;FLAGS;ARGS" ${ARGN})
    if(NOT P_ARCH)
        set(P_ARCH rv32im)
    endif()
    set(prog design_mig6_${NAME})
    dc_add_riscv_program(${prog}
                         SOURCES ${SW}/crt0.S ${SW}/semihosting/riscv_semihosting.c
                                 ${CMAKE_CURRENT_SOURCE_DIR}/mig6_exit.c ${P_SOURCES}
                         ARCH ${P_ARCH} FLAGS -O2 -ffreestanding -I${SW}/semihosting ${P_FLAGS}
                         LINK_FLAGS -T ${SW}/mig6.ld)
    cmake_language(CALL dc_add_${SIM}_run ${prog} BUILD design_mig6_sim
                   ARGS +hex=${CMAKE_CURRENT_BINARY_DIR}/${prog}.hex ${P_ARGS})
endfunction()

# Every PE prints its hart ID and exits with 0; every hart ID must exit once.
mig6_program_test(mhartid SOURCES mhartid.c)
