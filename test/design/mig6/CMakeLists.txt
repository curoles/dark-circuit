set(LIB  ${DARK_CIRCUIT_RTL_LIB})
set(MIG6 ${DARK_CIRCUIT_RTL_DESIGN}/mig6)
set(SW   ${PROJECT_SOURCE_DIR}/sw/riscv)

# Mig6 is a prototype (rtl/design/mig6/README.md): its core (Mig6Core, a copy of Mig3's), the
# network, and programs on the PEs of Mig6 (TbMig6).

# Files generated from cfg/mig6_config.yaml, from cfg/mig6_csr.yaml (the core CSRs:
# Mig6CsrPkg, sw/riscv/mig6/mig6_csr*.h) and from cfg/mig6_pma.yaml (the memory map: Mig6PmaPkg,
# sw/riscv/mig6/mig6_pma.h) are up to date.
dc_add_config_check(design_mig6 CONFIG ${MIG6}/cfg/mig6_config.yaml)
dc_add_config_check(design_mig6_csr CONFIG ${MIG6}/cfg/mig6_csr.yaml TOOL csr_gen)
dc_add_config_check(design_mig6_pma CONFIG ${MIG6}/cfg/mig6_pma.yaml TOOL pma_gen)

# Hardware files of Mig6Core: struct versions of the library, built from generic gates, the
# fp32 blocks (one version: hybrid), RISC-V formats and encodings (no P: kb
# rtl/design/mig6/no_p).
set(SYNTH_FLISTS ${LIB}/gate/generic/gate_generic.flist ${LIB}/part/part.flist
                 ${LIB}/block/block_struct.flist ${LIB}/numeric/numeric_struct.flist
                 ${LIB}/numeric/fp32/fp32.flist
                 ${LIB}/riscv/riscv.flist ${MIG6}/mig6.flist)

# Mig6Core converts to Verilog-2005 with sv2v and elaborates.
dc_add_sv2v_check(design_mig6 TOP Mig6Core FLISTS ${SYNTH_FLISTS})

# Synthesis of Mig6Core: build target design_mig6.synth (make mig6_synth), not a test. The
# tag and data RAMs of the caches are memory macros in a chip: black boxes.
dc_add_yosys_synth(design_mig6 TOP Mig6Core FLISTS ${SYNTH_FLISTS}
                   BLACKBOX_RAM_MODULES CacheTagRam CacheDataRam)

# Simulation: behave versions of the library (fast to simulate).
set(FLISTS ${LIB}/sim/sim.flist ${LIB}/gate/generic/gate_generic.flist ${LIB}/part/part.flist
           ${LIB}/block/block_behave.flist ${LIB}/numeric/numeric_behave.flist
           ${LIB}/numeric/fp32/fp32.flist
           ${LIB}/riscv/riscv.flist ${MIG6}/mig6.flist)

# Network tests with stand-in cores (TbMig6StandIn) in place of the PEs; Verilator only, as
# NocMesh's test (thousands of random requests): the two network interfaces joined without
# a mesh; four PEs' network interfaces on Mig6Noc, the shared memory at its edge.
set(STAND_IN ${CMAKE_CURRENT_SOURCE_DIR}/tb/tb_mig6_stand_in.flist)
dc_add_verilator_test(design_mig6_net_if TOP TbMig6NetIf TB tb/tb_mig6_net_if.sv
                      FLISTS ${FLISTS} ${STAND_IN})
dc_add_verilator_test(design_mig6_noc TOP TbMig6Noc TB tb/tb_mig6_noc.sv
                      FLISTS ${FLISTS} ${STAND_IN})

# Mig6 runs on the main simulator only, as Mig3 (see cmake/dark_circuit.cmake); programs need
# the RISC-V toolchain.
if(NOT DARK_CIRCUIT_MAINSIM OR NOT DARK_CIRCUIT_RISCV)
    message(STATUS "Mig6: no main simulator or no RISC-V toolchain, Mig6 programs are disabled")
    return()
endif()
set(SIM ${DARK_CIRCUIT_MAINSIM})

# Simulation of the PEs.
cmake_language(CALL dc_add_${SIM}_build design_mig6_sim TOP TbMig6 TB tb/tb_mig6.sv
               FLISTS ${FLISTS} ${CMAKE_CURRENT_SOURCE_DIR}/tb/tb_mig6.flist)

# mig6_program_test(<name> SOURCES <file>... [ARCH <march>] [FLAGS <flag>...] [ARGS <arg>...])
#
# A C or C++ program on every PE of TbMig6: crt0, semihosting, tprintf and Mig6's exit (the
# hart's ID in a2, mig6_exit.c) with the program's SOURCES, linked by sw/riscv/mig6/mig6.ld,
# sw/riscv on the include path (mig6/mig6_csr_ops.h, tprintf.h); the test passes when
# every hart exits with 0 (TbMig6). ARCH is -march of the program, default rv32ima: the
# core has A, and C atomics (__atomic_*) become AMOs. The compiler makes LR/SC loops of the
# others (compare-and-swap, a byte's add), allowed only in the local memory
# (Mig6Atomic: a_lr_sc_reservable).
function(mig6_program_test NAME)
    cmake_parse_arguments(P "" "ARCH" "SOURCES;FLAGS;ARGS" ${ARGN})
    if(NOT P_ARCH)
        set(P_ARCH rv32ima)
    endif()
    set(prog design_mig6_${NAME})
    dc_add_riscv_program(${prog}
                         SOURCES ${SW}/crt0.S ${SW}/semihosting/riscv_semihosting.c
                                 ${SW}/tprintf/tprintf.c
                                 ${CMAKE_CURRENT_SOURCE_DIR}/mig6_exit.c ${P_SOURCES}
                         ARCH ${P_ARCH}
                         FLAGS -O2 -ffreestanding -I${SW} -I${SW}/semihosting -I${SW}/tprintf
                               ${P_FLAGS}
                         LINK_FLAGS -T ${SW}/mig6/mig6.ld)
    cmake_language(CALL dc_add_${SIM}_run ${prog} BUILD design_mig6_sim
                   ARGS +hex=${CMAKE_CURRENT_BINARY_DIR}/${prog}.hex ${P_ARGS})
endfunction()

# Every PE prints its hart ID and its node (mnodeid) and exits with 0 when the node is the
# hart's; every hart ID must exit once.
mig6_program_test(mhartid SOURCES mhartid.c)

# Every standard CSR read by the assembler's name and by mig6_csr.h's address (from
# cfg/mig6_csr.yaml) gives the same value, inside its valid bits.
mig6_program_test(csr_names SOURCES csr_names.c)

# C++ on Mig6 (bare metal, no global constructors): a template dot product, at compile time
# and on the core, must agree.
mig6_program_test(cpp_basics SOURCES cpp_basics.cpp)

# The C++ CSR header (mig6::csr::<name>): read, write, set, clear and fields of a few CSRs.
mig6_program_test(csr_ops SOURCES csr_ops.cpp)

# tprintf (sw/riscv/tprintf): tsnprintf's text for integers, strings, %p, truncation and %a
# of float bits must be the expected one.
mig6_program_test(tprintf_check SOURCES tprintf_check.cpp)

# The C++ memory map (mig6::pma): its regions and pma_of when compiled, pointers into the
# shared memory, a stack variable in the local memory.
mig6_program_test(pma_check SOURCES pma_check.cpp)

# A barrier on the shared memory (an amoadd on a counter, loads until every hart arrived):
# after it every hart sees the stamps every hart stored before it.
mig6_program_test(barrier SOURCES barrier.cpp)

# The semihosting timeout (semihost::Timeout on SYS_CLOCK, the testbench's simulated time):
# a true condition returns at once, a false one gives up after its milliseconds.
mig6_program_test(timeout_check SOURCES timeout_check.cpp)

# Compare-and-swap on the shared memory (LR/SC done at the memory, its exclusive monitor):
# four harts count to the same total with CAS loops as with amoadd; a CAS in the local
# memory (the core's own reservation) too.
mig6_program_test(cas_check SOURCES cas_check.cpp)
