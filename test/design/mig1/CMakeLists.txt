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

    # Programs run on TbMig1, built once per simulator.
    foreach(sim IN ITEMS icarus verilator)
        cmake_language(CALL dc_add_${sim}_build design_mig1_sim TOP TbMig1 TB tb_mig1.sv
                       FLISTS ${FLISTS})
    endforeach()

    # mig1_program_test(<name> SOURCES <file>... [FLAGS <flag>...] [ARGS <arg>...]
    #                   [LABELS <label>...])
    #
    # Build RISC-V program design_mig1_<name> and add tests design_mig1_<name>.<sim>
    # that run it on TbMig1 with both simulators; ARGS get +hex=<program hex> and
    # +trace=<test>.<sim>.trace in the build directory; LABELS are added to the tests.
    function(mig1_program_test NAME)
        cmake_parse_arguments(P "" "" "SOURCES;FLAGS;ARGS;LABELS" ${ARGN})
        set(prog design_mig1_${NAME})
        dc_add_riscv_program(${prog} SOURCES ${P_SOURCES} FLAGS ${P_FLAGS}
                             LINK_FLAGS -T ${SW}/mig1.ld)
        foreach(sim IN ITEMS icarus verilator)
            cmake_language(CALL dc_add_${sim}_run ${prog} BUILD design_mig1_sim
                           ARGS +hex=${CMAKE_CURRENT_BINARY_DIR}/${prog}.hex
                                +trace=${CMAKE_CURRENT_BINARY_DIR}/${prog}.${sim}.trace
                                ${P_ARGS}
                           LABELS ${P_LABELS})
        endforeach()
    endfunction()

    # Fetch: straight-line program, every instruction retires, halt at EBREAK.
    mig1_program_test(fetch SOURCES fetch.S
                      ARGS +expect_sequential +expect_retired=5 +expect_halt_pc=10)

    # ALU program: OP, OP-IMM, LUI, AUIPC execute, registers checked at halt.
    mig1_program_test(alu_prog SOURCES alu.S ARGS +expect_sequential +expect_regs)

    # Branches and jumps: every branch type taken and not taken, JAL, JALR.
    mig1_program_test(branch SOURCES branch.S ARGS +expect_regs)

    # Loads and stores: every size and offset, sign extension, strobes.
    mig1_program_test(load_store SOURCES load_store.S ARGS +expect_sequential +expect_regs)

    # Faults stop the core at 0xc with illegal=1, rd and memory not written; one build
    # of the program per case (-DCASE_<case>):
    # misaligned jump target, load and store address; ECALL and illegal words.
    set(FAULT_ARGS +expect_illegal +expect_halt_pc=c +expect_regs +expect_mem_unchanged)
    foreach(case IN ITEMS jalr lw sh)
        string(TOUPPER ${case} case_macro)
        mig1_program_test(misaligned_${case} SOURCES misaligned.S FLAGS -DCASE_${case_macro}
                          ARGS ${FAULT_ARGS})
    endforeach()
    foreach(case IN ITEMS ecall zero ones)
        string(TOUPPER ${case} case_macro)
        mig1_program_test(illegal_${case} SOURCES illegal.S FLAGS -DCASE_${case_macro}
                          ARGS ${FAULT_ARGS})
    endforeach()

    # Debug port and resume: the testbench changes a0 at two EBREAKs and resumes.
    mig1_program_test(resume SOURCES resume.S
                      ARGS +resumes=2 +expect_sequential +expect_retired=6
                           +expect_halt_pc=14 +expect_regs)

    # riscv-tests rv32ui: one self-checking test per instruction, labels riscv-tests and
    # rv32ui; riscv_test.h of this directory is their environment.
    # Not run: fence_i (writes code into memory; Mig1 fetches from a separate
    # instruction memory), ma_data (misaligned loads and stores; Mig1 stops on them).
    set(RISCV_TESTS ${PROJECT_SOURCE_DIR}/test/third_party/riscv-tests/isa)
    foreach(test IN ITEMS simple add addi and andi auipc beq bge bgeu blt bltu bne jal jalr
                          lb lbu lh lhu lw ld_st lui or ori sb sh sw st_ld sll slli slt slti
                          sltiu sltu sra srai srl srli sub xor xori)
        mig1_program_test(rv32ui_${test} SOURCES ${RISCV_TESTS}/rv32ui/${test}.S
                          FLAGS -I${CMAKE_CURRENT_SOURCE_DIR} -I${RISCV_TESTS}/macros/scalar
                          ARGS +riscv_test
                          LABELS riscv-tests rv32ui)
    endforeach()
endif()
