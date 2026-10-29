set(LIB  ${DARK_CIRCUIT_RTL_LIB})
set(MIG1 ${DARK_CIRCUIT_RTL_DESIGN}/mig1)
set(SW   ${PROJECT_SOURCE_DIR}/sw/riscv)

# Mig1 uses blocks of the library (behave versions are fast to simulate)
# and RISC-V formats and encodings.
set(FLISTS ${LIB}/sim/sim.flist ${LIB}/block/block_behave.flist ${LIB}/numeric/numeric_behave.flist
           ${LIB}/riscv/riscv.flist ${MIG1}/mig1.flist)

# Files generated from cfg/mig1_config.yaml are up to date.
dc_add_config_check(design_mig1 CONFIG ${MIG1}/cfg/mig1_config.yaml)

# Hardware files of Mig1Core: struct versions of the library, built from generic gates
# (not the fast simulation models). Mig1Cpu is not included: its memories are simulation models.
set(SYNTH_FLISTS ${LIB}/gate/generic/gate_generic.flist ${LIB}/part/part.flist
                 ${LIB}/block/block_struct.flist ${LIB}/numeric/numeric_struct.flist
                 ${LIB}/riscv/riscv.flist ${MIG1}/mig1.flist)

# Mig1Core converts to Verilog-2005 with sv2v and elaborates: the syntax of Mig1 is what
# sv2v supports.
dc_add_sv2v_check(design_mig1 TOP Mig1Core FLISTS ${SYNTH_FLISTS})

# Synthesis of Mig1Core: build target design_mig1.synth (make mig1_synth), not a test.
dc_add_yosys_synth(design_mig1 TOP Mig1Core FLISTS ${SYNTH_FLISTS})

# Mig1 runs on the main simulator only: DARK_CIRCUIT_MAIN_SIMULATOR, by default
# Verilator when it is installed (see cmake/dark_circuit.cmake).
if(NOT DARK_CIRCUIT_MAINSIM)
    message(STATUS "Mig1: no main simulator, Mig1 tests are disabled")
    return()
endif()
set(SIM ${DARK_CIRCUIT_MAINSIM})

# Registers and ALU: unit tests of Mig1Regs and Mig1Alu, no program.
dc_add_mainsim_test(design_mig1_regs TOP TbMig1Regs TB tb/tb_mig1_regs.sv FLISTS ${FLISTS})
dc_add_mainsim_test(design_mig1_alu TOP TbMig1Alu TB tb/tb_mig1_alu.sv FLISTS ${FLISTS})

# Programs need the RISC-V toolchain.
if(DARK_CIRCUIT_RISCV)
    # Mig1Cpu memories: load() of a program.
    dc_add_riscv_program(design_mig1_mem SOURCES mem.S LINK_FLAGS -T ${SW}/mig1.ld)
    dc_add_mainsim_test(design_mig1_mem TOP TbMig1Mem TB tb/tb_mig1_mem.sv
                        FLISTS ${FLISTS}
                        ARGS +hex=${CMAKE_CURRENT_BINARY_DIR}/design_mig1_mem.hex)

    # Decode: unit test of Mig1Decode with cases encoded by the assembler.
    dc_add_riscv_program(design_mig1_decode SOURCES decode.S ARCH rv32im LINK_FLAGS -T ${SW}/mig1.ld)
    dc_add_mainsim_test(design_mig1_decode TOP TbMig1Decode TB tb/tb_mig1_decode.sv
                        FLISTS ${FLISTS}
                        ARGS +hex=${CMAKE_CURRENT_BINARY_DIR}/design_mig1_decode.hex)

    # Programs run on TbMig1, built once; tb/tb_mig1.flist has the modules it instantiates.
    cmake_language(CALL dc_add_${SIM}_build design_mig1_sim TOP TbMig1 TB tb/tb_mig1.sv
                   FLISTS ${FLISTS} ${CMAKE_CURRENT_SOURCE_DIR}/tb/tb_mig1.flist)

    # Logs cost a file per test: written only with these options.
    option(DARK_CIRCUIT_MIG1_TRACE "Mig1 program tests write a trace (+trace)" OFF)
    option(DARK_CIRCUIT_MIG1_KANATA "Mig1 program tests write a Konata log (+kanata)" OFF)

    # mig1_program_test(<name> SOURCES <file>... [ARCH <march>] [FLAGS <flag>...]
    #                   [ARGS <arg>...] [LABELS <label>...] [OUTPUT <regex>])
    #
    # Build RISC-V program design_mig1_<name> and add test design_mig1_<name>.<sim>
    # that runs it on TbMig1 with the main simulator; ARGS get +hex=<program hex> and
    # +symbols=<program symbols>, with DARK_CIRCUIT_MIG1_TRACE +trace=<test>.<sim>.trace,
    # with DARK_CIRCUIT_MIG1_KANATA +kanata=<test>.<sim>.kanata, all in the build directory;
    # ARCH is -march of the program (default rv32i);
    # LABELS are added to the tests;
    # with OUTPUT the output (semihosting console) must match <regex>.
    function(mig1_program_test NAME)
        cmake_parse_arguments(P "" "OUTPUT;ARCH" "SOURCES;FLAGS;ARGS;LABELS" ${ARGN})
        if(NOT P_ARCH)
            set(P_ARCH rv32i)
        endif()
        set(prog design_mig1_${NAME})
        dc_add_riscv_program(${prog} SOURCES ${P_SOURCES} ARCH ${P_ARCH} FLAGS ${P_FLAGS}
                             LINK_FLAGS -T ${SW}/mig1.ld)
        set(logs)
        if(DARK_CIRCUIT_MIG1_TRACE)
            list(APPEND logs +trace=${CMAKE_CURRENT_BINARY_DIR}/${prog}.${SIM}.trace)
        endif()
        if(DARK_CIRCUIT_MIG1_KANATA)
            list(APPEND logs +kanata=${CMAKE_CURRENT_BINARY_DIR}/${prog}.${SIM}.kanata)
        endif()
        cmake_language(CALL dc_add_${SIM}_run ${prog} BUILD design_mig1_sim
                       ARGS +hex=${CMAKE_CURRENT_BINARY_DIR}/${prog}.hex
                            +symbols=${CMAKE_CURRENT_BINARY_DIR}/${prog}.sym
                            ${logs} ${P_ARGS}
                       LABELS ${P_LABELS} OUTPUT ${P_OUTPUT})
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

    # Faults trap: a handler checks mcause, mepc and mtval; rd and memory are not
    # written. One build of the program per case (-DCASE_<case>):
    # misaligned jump target, load and store address; ECALL, illegal words, CSR
    # instructions on a missing CSR or writing a read-only one.
    set(FAULT_ARGS +expect_trap +expect_regs +expect_mem_unchanged)
    foreach(case IN ITEMS jalr lw sh)
        string(TOUPPER ${case} case_macro)
        mig1_program_test(misaligned_${case} SOURCES misaligned.S FLAGS -DCASE_${case_macro}
                          ARGS ${FAULT_ARGS})
    endforeach()
    foreach(case IN ITEMS ecall zero ones csr_unknown csr_readonly)
        string(TOUPPER ${case} case_macro)
        mig1_program_test(illegal_${case} SOURCES illegal.S FLAGS -DCASE_${case_macro}
                          ARGS ${FAULT_ARGS})
    endforeach()

    # Debug port and resume: the testbench changes a0 at two EBREAKs and resumes.
    mig1_program_test(resume SOURCES resume.S
                      ARGS +resumes=2 +expect_sequential +expect_retired=6
                           +expect_halt_pc=14 +expect_regs)

    # CSRs and counters: Zicsr instructions on mscratch, read-only CSRs, Zicntr.
    mig1_program_test(csr SOURCES csr.S ARGS +expect_regs)

    # M extension: results used right away, division and branches, cycle cost, minstret.
    mig1_program_test(muldiv SOURCES muldiv.S ARCH rv32im ARGS +expect_regs)

    # Traps: mtvec, mepc, mstatus through ECALL and MRET, WFI, EBREAK as a breakpoint trap.
    mig1_program_test(trap SOURCES trap.S ARGS +expect_trap +first_ebreak_traps +expect_regs)

    # JAL in the corners of the pipeline: on the wrong path, behind a division, to a
    # misaligned target, after a halting EBREAK, back to back, its link used right away.
    mig1_program_test(jal_id SOURCES jal_id.S ARCH rv32im
                      ARGS +expect_trap +resumes=1 +expect_regs)

    # Conditional branches in the corners of the pipeline: every pair of guess and outcome
    # of a static guess, waiting in ID (load-use, division), on the wrong path, back to back,
    # to misaligned targets. +max_cycles is a cycle ceiling (Mig1 README): lower it when a
    # change makes the test faster.
    mig1_program_test(branch_id SOURCES branch_id.S ARCH rv32im
                      ARGS +expect_trap +expect_regs +max_cycles=180)

    # Semihosting: the C program of test/sw/riscv/semihosting (QEMU) prints and exits
    # with 3 on Mig1 too; crt0.S and the semihosting library of sw/riscv.
    mig1_program_test(semihosting
                      SOURCES ${SW}/crt0.S ${SW}/semihosting/riscv_semihosting.c
                              ${PROJECT_SOURCE_DIR}/test/sw/riscv/semihosting/test_semihosting.c
                      FLAGS -O2 -Wall -Wextra -ffreestanding -I${SW}/semihosting
                      ARGS +expect_exit=3
                      OUTPUT "semihost_write0 works[\r\n]+OK")

    # Semihosting SYS_EXIT (0x18): on RV32 only the reason, in a1; ADP_Stopped_ApplicationExit
    # is exit 0, any other reason exit 1 (the semihosting test uses SYS_EXIT_EXTENDED).
    mig1_program_test(sys_exit SOURCES sys_exit.S FLAGS -DREASON=0x20026 ARGS +expect_exit=0)
    mig1_program_test(sys_exit_error SOURCES sys_exit.S FLAGS -DREASON=0x20023
                      ARGS +expect_exit=1)

    # riscv-tests with their standard environment env/p (source fetched by cmake/fetch.cmake):
    # self-checking, each test ends with a store to tohost. Labels riscv-tests and the suite.
    dc_riscv_tests()
    if(DARK_CIRCUIT_RISCV_TESTS)
        set(RISCV_TESTS ${RISCV_TESTS_DIR})
        set(RISCV_TESTS_FLAGS -I${RISCV_TESTS}/env/p -I${RISCV_TESTS}/isa/macros/scalar)
        set(RISCV_TESTS_ARGS +riscv_test +no_debugger)

        # rv32ui: one test per instruction. Not run: fence_i (writes code into memory; Mig1
        # fetches from a separate instruction memory), ma_data (misaligned loads and stores;
        # Mig1 traps on them).
        foreach(test IN ITEMS simple add addi and andi auipc beq bge bgeu blt bltu bne jal jalr
                              lb lbu lh lhu lw ld_st lui or ori sb sh sw st_ld sll slli slt slti
                              sltiu sltu sra srai srl srli sub xor xori)
            mig1_program_test(rv32ui_${test} SOURCES ${RISCV_TESTS}/isa/rv32ui/${test}.S
                              FLAGS ${RISCV_TESTS_FLAGS} ARGS ${RISCV_TESTS_ARGS}
                              LABELS riscv-tests rv32ui)
        endforeach()

        # rv32mi: machine mode, CSRs, traps. Not run: breakpoint (needs the trigger CSRs of
        # Sdtrig), pmpaddr (needs PMP); both are optional and Mig1 does not have them.
        foreach(test IN ITEMS csr illegal instret_overflow lh-misaligned lw-misaligned ma_addr
                              ma_fetch mcsr sbreak scall sh-misaligned shamt sw-misaligned zicntr)
            mig1_program_test(rv32mi_${test} SOURCES ${RISCV_TESTS}/isa/rv32mi/${test}.S
                              FLAGS ${RISCV_TESTS_FLAGS} ARGS ${RISCV_TESTS_ARGS}
                              LABELS riscv-tests rv32mi)
        endforeach()

        # Benchmarks, with DARK_CIRCUIT_BENCHMARKS only (not regular testing). Dhrystone of
        # riscv-tests/benchmarks, unchanged, with sw/riscv/bench: real code with branches and
        # calls, to measure cycles (its own results are not printed). One run of bench_main
        # is 500 Dhrystone loops; BENCH_REPEAT runs, about 5 s on Verilator. +max_cycles is a
        # cycle ceiling per gcc version (Mig1 README, dc_riscv_cycle_ceiling): the cycles + 1 %,
        # rounded up to 1000. Lower it when a change makes the benchmark faster; add the
        # version of a new compiler.
        if(DARK_CIRCUIT_BENCHMARKS)
            set(DHRY ${RISCV_TESTS}/benchmarks/dhrystone)
            dc_riscv_cycle_ceiling(dhry_cycles design_mig1_dhrystone
                                   10.2.0 2156000 12.2.0 2238000)
            mig1_program_test(dhrystone
                              SOURCES ${SW}/crt0.S ${SW}/semihosting/riscv_semihosting.c
                                      ${SW}/bench/bench.c ${DHRY}/dhrystone.c
                                      ${DHRY}/dhrystone_main.c
                              ARCH rv32im
                              FLAGS -O2 -ffreestanding -fno-builtin-printf
                                    -include ${SW}/bench/bench_main.h -DBENCH_REPEAT=6
                                    -Wno-implicit-int -Wno-implicit-function-declaration
                                    -I${SW}/bench/include -I${SW}/semihosting -I${DHRY}
                                    -I${RISCV_TESTS}/benchmarks/common -I${RISCV_TESTS}/env
                              ARGS +expect_exit=0 +max_cycles=${dhry_cycles}
                              LABELS benchmark)
        endif()

        # rv32um: multiply and divide.
        foreach(test IN ITEMS mul mulh mulhsu mulhu div divu rem remu)
            mig1_program_test(rv32um_${test} SOURCES ${RISCV_TESTS}/isa/rv32um/${test}.S
                              ARCH rv32im FLAGS ${RISCV_TESTS_FLAGS} ARGS ${RISCV_TESTS_ARGS}
                              LABELS riscv-tests rv32um)
        endforeach()
    endif()
endif()
