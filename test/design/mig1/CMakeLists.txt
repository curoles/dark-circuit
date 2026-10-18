set(LIB  ${DARK_CIRCUIT_RTL_LIB})
set(MIG1 ${DARK_CIRCUIT_RTL_DESIGN}/mig1)
set(SW   ${PROJECT_SOURCE_DIR}/sw/riscv)

# Mig1 uses blocks of the library (behave versions are fast to simulate)
# and RISC-V formats and encodings.
set(FLISTS ${LIB}/sim/sim.flist ${LIB}/block/block_behave.flist ${LIB}/riscv/riscv.flist
           ${MIG1}/mig1.flist)

# Files generated from cfg/mig1_config.yaml are up to date.
dc_add_config_check(design_mig1 CONFIG ${MIG1}/cfg/mig1_config.yaml)

# Registers and ALU: unit tests of Mig1Regs and Mig1Alu, no program.
foreach(sim IN ITEMS icarus verilator)
    cmake_language(CALL dc_add_${sim}_test design_mig1_regs TOP TbMig1Regs TB tb_mig1_regs.sv
                   FLISTS ${FLISTS})
    cmake_language(CALL dc_add_${sim}_test design_mig1_alu TOP TbMig1Alu TB tb_mig1_alu.sv
                   FLISTS ${FLISTS})
endforeach()

# Programs need the RISC-V toolchain.
if(DARK_CIRCUIT_RISCV)
    # Mig1Cpu memories: load() of a program.
    dc_add_riscv_program(design_mig1_mem SOURCES mem.S LINK_FLAGS -T ${SW}/mig1.ld)
    foreach(sim IN ITEMS icarus verilator)
        cmake_language(CALL dc_add_${sim}_test design_mig1_mem TOP TbMig1Mem TB tb_mig1_mem.sv
                       FLISTS ${FLISTS}
                       ARGS +hex=${CMAKE_CURRENT_BINARY_DIR}/design_mig1_mem.hex)
    endforeach()

    # Decode: unit test of Mig1Decode with cases encoded by the assembler.
    dc_add_riscv_program(design_mig1_decode SOURCES decode.S LINK_FLAGS -T ${SW}/mig1.ld)
    foreach(sim IN ITEMS icarus verilator)
        cmake_language(CALL dc_add_${sim}_test design_mig1_decode TOP TbMig1Decode TB tb_mig1_decode.sv
                       FLISTS ${FLISTS}
                       ARGS +hex=${CMAKE_CURRENT_BINARY_DIR}/design_mig1_decode.hex)
    endforeach()

    # Fetch: straight-line program, every instruction retires, halt at EBREAK.
    dc_add_riscv_program(design_mig1_fetch SOURCES fetch.S LINK_FLAGS -T ${SW}/mig1.ld)
    foreach(sim IN ITEMS icarus verilator)
        cmake_language(CALL dc_add_${sim}_test design_mig1_fetch TOP TbMig1 TB tb_mig1.sv
                       FLISTS ${FLISTS}
                       ARGS +hex=${CMAKE_CURRENT_BINARY_DIR}/design_mig1_fetch.hex
                            +trace=${CMAKE_CURRENT_BINARY_DIR}/design_mig1_fetch.${sim}.trace
                            +expect_sequential +expect_retired=5 +expect_halt_pc=10)
    endforeach()

    # ALU program: OP, OP-IMM, LUI, AUIPC execute, registers checked at halt.
    dc_add_riscv_program(design_mig1_alu_prog SOURCES alu.S LINK_FLAGS -T ${SW}/mig1.ld)
    foreach(sim IN ITEMS icarus verilator)
        cmake_language(CALL dc_add_${sim}_test design_mig1_alu_prog TOP TbMig1 TB tb_mig1.sv
                       FLISTS ${FLISTS}
                       ARGS +hex=${CMAKE_CURRENT_BINARY_DIR}/design_mig1_alu_prog.hex
                            +trace=${CMAKE_CURRENT_BINARY_DIR}/design_mig1_alu_prog.${sim}.trace
                            +expect_sequential +expect_regs)
    endforeach()

    # Branches and jumps: every branch type taken and not taken, JAL, JALR.
    dc_add_riscv_program(design_mig1_branch SOURCES branch.S LINK_FLAGS -T ${SW}/mig1.ld)
    foreach(sim IN ITEMS icarus verilator)
        cmake_language(CALL dc_add_${sim}_test design_mig1_branch TOP TbMig1 TB tb_mig1.sv
                       FLISTS ${FLISTS}
                       ARGS +hex=${CMAKE_CURRENT_BINARY_DIR}/design_mig1_branch.hex
                            +trace=${CMAKE_CURRENT_BINARY_DIR}/design_mig1_branch.${sim}.trace
                            +expect_regs)
    endforeach()

    # Loads and stores: every size and offset, sign extension, strobes.
    dc_add_riscv_program(design_mig1_load_store SOURCES load_store.S LINK_FLAGS -T ${SW}/mig1.ld)
    foreach(sim IN ITEMS icarus verilator)
        cmake_language(CALL dc_add_${sim}_test design_mig1_load_store TOP TbMig1 TB tb_mig1.sv
                       FLISTS ${FLISTS}
                       ARGS +hex=${CMAKE_CURRENT_BINARY_DIR}/design_mig1_load_store.hex
                            +trace=${CMAKE_CURRENT_BINARY_DIR}/design_mig1_load_store.${sim}.trace
                            +expect_sequential +expect_regs)
    endforeach()

    # Misaligned jump target, load and store address: halt with illegal=1 at the
    # instruction, rd and memory not written. One build of misaligned.S per case (-DCASE_<case>).
    foreach(case IN ITEMS jalr lw sh)
        string(TOUPPER ${case} case_macro)
        set(prog design_mig1_misaligned_${case})
        dc_add_riscv_program(${prog} SOURCES misaligned.S FLAGS -DCASE_${case_macro}
                             LINK_FLAGS -T ${SW}/mig1.ld)
        foreach(sim IN ITEMS icarus verilator)
            cmake_language(CALL dc_add_${sim}_test ${prog} TOP TbMig1 TB tb_mig1.sv
                           FLISTS ${FLISTS}
                           ARGS +hex=${CMAKE_CURRENT_BINARY_DIR}/${prog}.hex
                                +trace=${CMAKE_CURRENT_BINARY_DIR}/${prog}.${sim}.trace
                                +expect_illegal +expect_halt_pc=c +expect_regs
                                +expect_mem_unchanged)
        endforeach()
    endforeach()
endif()
