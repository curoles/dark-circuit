set(LIB  ${DARK_CIRCUIT_RTL_LIB})
set(MIG2 ${DARK_CIRCUIT_RTL_DESIGN}/mig2)
set(SW   ${PROJECT_SOURCE_DIR}/sw/riscv)

# Mig2 uses blocks of the library (behave versions are fast to simulate)
# and RISC-V formats and encodings.
set(FLISTS ${LIB}/sim/sim.flist ${LIB}/block/block_behave.flist ${LIB}/numeric/numeric_behave.flist
           ${LIB}/riscv/riscv.flist ${MIG2}/mig2.flist)

# Files generated from cfg/mig2_config.yaml are up to date.
dc_add_config_check(design_mig2 CONFIG ${MIG2}/cfg/mig2_config.yaml)

# Hardware files of Mig2Core: struct versions of the library, built from generic gates
# (not the fast simulation models). Mig2Cpu is not included: its memories are simulation models.
set(SYNTH_FLISTS ${LIB}/gate/generic/gate_generic.flist ${LIB}/part/part.flist
                 ${LIB}/block/block_struct.flist ${LIB}/numeric/numeric_struct.flist
                 ${LIB}/riscv/riscv.flist ${MIG2}/mig2.flist)

# Mig2Core converts to Verilog-2005 with sv2v and elaborates: the syntax of Mig2 is what
# sv2v supports.
dc_add_sv2v_check(design_mig2 TOP Mig2Core FLISTS ${SYNTH_FLISTS})

# Synthesis of Mig2Core: build target design_mig2.synth (make mig2_synth), not a test.
dc_add_yosys_synth(design_mig2 TOP Mig2Core FLISTS ${SYNTH_FLISTS})

# Mig2 runs on the main simulator only: DARK_CIRCUIT_MAIN_SIMULATOR, by default
# Verilator when it is installed (see cmake/dark_circuit.cmake).
if(NOT DARK_CIRCUIT_MAINSIM)
    message(STATUS "Mig2: no main simulator, Mig2 tests are disabled")
    return()
endif()
set(SIM ${DARK_CIRCUIT_MAINSIM})

# Registers and ALU: unit tests of Mig2Regs and Mig2Alu, no program.
dc_add_mainsim_test(design_mig2_regs TOP TbMig2Regs TB tb_mig2_regs.sv FLISTS ${FLISTS})
dc_add_mainsim_test(design_mig2_alu TOP TbMig2Alu TB tb_mig2_alu.sv FLISTS ${FLISTS})

# Programs need the RISC-V toolchain.
if(DARK_CIRCUIT_RISCV)
    # Mig2Cpu memories: load() of a program.
    dc_add_riscv_program(design_mig2_mem SOURCES mem.S LINK_FLAGS -T ${SW}/mig2.ld)
    dc_add_mainsim_test(design_mig2_mem TOP TbMig2Mem TB tb_mig2_mem.sv
                        FLISTS ${FLISTS}
                        ARGS +hex=${CMAKE_CURRENT_BINARY_DIR}/design_mig2_mem.hex)

    # Decode: unit test of Mig2Decode with cases encoded by the assembler.
    dc_add_riscv_program(design_mig2_decode SOURCES decode.S ARCH rv32im LINK_FLAGS -T ${SW}/mig2.ld)
    dc_add_mainsim_test(design_mig2_decode TOP TbMig2Decode TB tb_mig2_decode.sv
                        FLISTS ${FLISTS}
                        ARGS +hex=${CMAKE_CURRENT_BINARY_DIR}/design_mig2_decode.hex)

    # Programs run on TbMig2, built once.
    cmake_language(CALL dc_add_${SIM}_build design_mig2_sim TOP TbMig2 TB tb_mig2.sv
                   FLISTS ${FLISTS})

    # Konata logs of the pipeline cost a file per test: written only with this option.
    option(DARK_CIRCUIT_MIG2_KANATA "Mig2 program tests write a Konata log (+kanata)" OFF)

    # mig2_program_test(<name> SOURCES <file>... [ARCH <march>] [FLAGS <flag>...]
    #                   [ARGS <arg>...] [LABELS <label>...] [OUTPUT <regex>])
    #
    # Build RISC-V program design_mig2_<name> and add test design_mig2_<name>.<sim>
    # that runs it on TbMig2 with the main simulator; ARGS get +hex=<program hex>,
    # +symbols=<program symbols> and +trace=<test>.<sim>.trace in the build directory,
    # with DARK_CIRCUIT_MIG2_KANATA also +kanata=<test>.<sim>.kanata;
    # ARCH is -march of the program (default rv32i);
    # LABELS are added to the tests;
    # with OUTPUT the output (semihosting console) must match <regex>.
    function(mig2_program_test NAME)
        cmake_parse_arguments(P "" "OUTPUT;ARCH" "SOURCES;FLAGS;ARGS;LABELS" ${ARGN})
        if(NOT P_ARCH)
            set(P_ARCH rv32i)
        endif()
        set(prog design_mig2_${NAME})
        dc_add_riscv_program(${prog} SOURCES ${P_SOURCES} ARCH ${P_ARCH} FLAGS ${P_FLAGS}
                             LINK_FLAGS -T ${SW}/mig2.ld)
        set(kanata)
        if(DARK_CIRCUIT_MIG2_KANATA)
            set(kanata +kanata=${CMAKE_CURRENT_BINARY_DIR}/${prog}.${SIM}.kanata)
        endif()
        cmake_language(CALL dc_add_${SIM}_run ${prog} BUILD design_mig2_sim
                       ARGS +hex=${CMAKE_CURRENT_BINARY_DIR}/${prog}.hex
                            +symbols=${CMAKE_CURRENT_BINARY_DIR}/${prog}.sym
                            +trace=${CMAKE_CURRENT_BINARY_DIR}/${prog}.${SIM}.trace
                            ${kanata} ${P_ARGS}
                       LABELS ${P_LABELS} OUTPUT ${P_OUTPUT})
    endfunction()

    # Fetch: straight-line program, every instruction retires, halt at EBREAK.
    mig2_program_test(fetch SOURCES fetch.S
                      ARGS +expect_sequential +expect_retired=5 +expect_halt_pc=10)

    # ALU program: OP, OP-IMM, LUI, AUIPC execute, registers checked at halt.
    mig2_program_test(alu_prog SOURCES alu.S ARGS +expect_sequential +expect_regs)

    # Branches and jumps: every branch type taken and not taken, JAL, JALR.
    mig2_program_test(branch SOURCES branch.S ARGS +expect_regs)

    # Loads and stores: every size and offset, sign extension, strobes.
    mig2_program_test(load_store SOURCES load_store.S ARGS +expect_sequential +expect_regs)

    # Faults trap: a handler checks mcause, mepc and mtval; rd and memory are not
    # written. One build of the program per case (-DCASE_<case>):
    # misaligned jump target, load and store address; ECALL, illegal words, CSR
    # instructions on a missing CSR or writing a read-only one.
    set(FAULT_ARGS +expect_trap +expect_regs +expect_mem_unchanged)
    foreach(case IN ITEMS jalr lw sh)
        string(TOUPPER ${case} case_macro)
        mig2_program_test(misaligned_${case} SOURCES misaligned.S FLAGS -DCASE_${case_macro}
                          ARGS ${FAULT_ARGS})
    endforeach()
    foreach(case IN ITEMS ecall zero ones csr_unknown csr_readonly)
        string(TOUPPER ${case} case_macro)
        mig2_program_test(illegal_${case} SOURCES illegal.S FLAGS -DCASE_${case_macro}
                          ARGS ${FAULT_ARGS})
    endforeach()

    # Debug port and resume: the testbench changes a0 at two EBREAKs and resumes.
    mig2_program_test(resume SOURCES resume.S
                      ARGS +resumes=2 +expect_sequential +expect_retired=6
                           +expect_halt_pc=14 +expect_regs)

    # CSRs and counters: Zicsr instructions on mscratch, read-only CSRs, Zicntr.
    mig2_program_test(csr SOURCES csr.S ARGS +expect_regs)

    # M extension: results used right away, division and branches, cycle cost, minstret.
    mig2_program_test(muldiv SOURCES muldiv.S ARCH rv32im ARGS +expect_regs)

    # Traps: mtvec, mepc, mstatus through ECALL and MRET, WFI, EBREAK as a breakpoint trap.
    mig2_program_test(trap SOURCES trap.S ARGS +expect_trap +first_ebreak_traps +expect_regs)

    # Semihosting: the C program of test/sw/riscv/semihosting (QEMU) prints and exits
    # with 3 on Mig2 too; crt0.S and the semihosting library of sw/riscv.
    mig2_program_test(semihosting
                      SOURCES ${SW}/crt0.S ${SW}/semihosting/riscv_semihosting.c
                              ${PROJECT_SOURCE_DIR}/test/sw/riscv/semihosting/test_semihosting.c
                      FLAGS -O2 -Wall -Wextra -ffreestanding -I${SW}/semihosting
                      ARGS +expect_exit=3
                      OUTPUT "semihost_write0 works[\r\n]+OK")

    # riscv-tests with their standard environment env/p (source fetched by cmake/fetch.cmake):
    # self-checking, each test ends with a store to tohost. Labels riscv-tests and the suite.
    dc_riscv_tests()
    if(DARK_CIRCUIT_RISCV_TESTS)
        set(RISCV_TESTS ${RISCV_TESTS_DIR})
        set(RISCV_TESTS_FLAGS -I${RISCV_TESTS}/env/p -I${RISCV_TESTS}/isa/macros/scalar)
        set(RISCV_TESTS_ARGS +riscv_test +no_debugger)

        # rv32ui: one test per instruction. Not run: fence_i (writes code into memory; Mig2
        # fetches from a separate instruction memory), ma_data (misaligned loads and stores;
        # Mig2 traps on them).
        foreach(test IN ITEMS simple add addi and andi auipc beq bge bgeu blt bltu bne jal jalr
                              lb lbu lh lhu lw ld_st lui or ori sb sh sw st_ld sll slli slt slti
                              sltiu sltu sra srai srl srli sub xor xori)
            mig2_program_test(rv32ui_${test} SOURCES ${RISCV_TESTS}/isa/rv32ui/${test}.S
                              FLAGS ${RISCV_TESTS_FLAGS} ARGS ${RISCV_TESTS_ARGS}
                              LABELS riscv-tests rv32ui)
        endforeach()

        # rv32mi: machine mode, CSRs, traps. Not run: breakpoint (needs the trigger CSRs of
        # Sdtrig), pmpaddr (needs PMP); both are optional and Mig2 does not have them.
        foreach(test IN ITEMS csr illegal instret_overflow lh-misaligned lw-misaligned ma_addr
                              ma_fetch mcsr sbreak scall sh-misaligned shamt sw-misaligned zicntr)
            mig2_program_test(rv32mi_${test} SOURCES ${RISCV_TESTS}/isa/rv32mi/${test}.S
                              FLAGS ${RISCV_TESTS_FLAGS} ARGS ${RISCV_TESTS_ARGS}
                              LABELS riscv-tests rv32mi)
        endforeach()

        # rv32um: multiply and divide.
        foreach(test IN ITEMS mul mulh mulhsu mulhu div divu rem remu)
            mig2_program_test(rv32um_${test} SOURCES ${RISCV_TESTS}/isa/rv32um/${test}.S
                              ARCH rv32im FLAGS ${RISCV_TESTS_FLAGS} ARGS ${RISCV_TESTS_ARGS}
                              LABELS riscv-tests rv32um)
        endforeach()
    endif()
endif()
