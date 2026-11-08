set(LIB  ${DARK_CIRCUIT_RTL_LIB})
set(MIG3 ${DARK_CIRCUIT_RTL_DESIGN}/mig3)
set(SW   ${PROJECT_SOURCE_DIR}/sw/riscv)

# Mig3 uses blocks of the library (behave versions are fast to simulate)
# and RISC-V formats and encodings.
set(FLISTS ${LIB}/sim/sim.flist ${LIB}/gate/generic/gate_generic.flist
           ${LIB}/block/block_behave.flist ${LIB}/numeric/numeric_behave.flist
           ${LIB}/riscv/riscv.flist ${MIG3}/mig3.flist)

# Files generated from cfg/mig3_config.yaml are up to date.
dc_add_config_check(design_mig3 CONFIG ${MIG3}/cfg/mig3_config.yaml)

# Hardware files of Mig3Core: struct versions of the library, built from generic gates
# (not the fast simulation models). Mig3Cpu is not included: its memories are simulation models.
set(SYNTH_FLISTS ${LIB}/gate/generic/gate_generic.flist ${LIB}/part/part.flist
                 ${LIB}/block/block_struct.flist ${LIB}/numeric/numeric_struct.flist
                 ${LIB}/riscv/riscv.flist ${MIG3}/mig3.flist)

# Mig3Core converts to Verilog-2005 with sv2v and elaborates: the syntax of Mig3 is what
# sv2v supports.
dc_add_sv2v_check(design_mig3 TOP Mig3Core FLISTS ${SYNTH_FLISTS})

# Synthesis of Mig3Core: build target design_mig3.synth (make mig3_synth), not a test. The
# tag and data RAMs of the caches are memory macros in a chip: black boxes.
dc_add_yosys_synth(design_mig3 TOP Mig3Core FLISTS ${SYNTH_FLISTS}
                   BLACKBOX_RAM_MODULES CacheTagRam CacheDataRam)

# Mig3 runs on the main simulator only: DARK_CIRCUIT_MAIN_SIMULATOR, by default
# Verilator when it is installed (see cmake/dark_circuit.cmake).
if(NOT DARK_CIRCUIT_MAINSIM)
    message(STATUS "Mig3: no main simulator, Mig3 tests are disabled")
    return()
endif()
set(SIM ${DARK_CIRCUIT_MAINSIM})

# Registers and ALU: unit tests of Mig3Regs and Mig3Alu, no program.
dc_add_mainsim_test(design_mig3_regs TOP TbMig3Regs TB tb/tb_mig3_regs.sv FLISTS ${FLISTS})
dc_add_mainsim_test(design_mig3_alu TOP TbMig3Alu TB tb/tb_mig3_alu.sv FLISTS ${FLISTS})

# Programs need the RISC-V toolchain.
if(DARK_CIRCUIT_RISCV)
    # Mig3Cpu memories: load() of a program.
    dc_add_riscv_program(design_mig3_mem SOURCES mem.S LINK_FLAGS -T ${SW}/mig3.ld)
    dc_add_mainsim_test(design_mig3_mem TOP TbMig3Mem TB tb/tb_mig3_mem.sv
                        FLISTS ${FLISTS}
                        ARGS +hex=${CMAKE_CURRENT_BINARY_DIR}/design_mig3_mem.hex)

    # Decode: unit test of Mig3Decode with cases encoded by the assembler (A for the LR/SC
    # cases); the Zbb cases only when the compiler knows Zbb (DARK_CIRCUIT_RISCV_ZBB,
    # cmake/riscv.cmake).
    # +zbb: the testbench then wants a case of KIND_BITMANIP too.
    if(DARK_CIRCUIT_RISCV_ZBB)
        dc_add_riscv_program(design_mig3_decode SOURCES decode.S ARCH rv32ima_zbb FLAGS -DHAVE_ZBB
                             LINK_FLAGS -T ${SW}/mig3.ld)
        set(decode_zbb +zbb)
    else()
        dc_add_riscv_program(design_mig3_decode SOURCES decode.S ARCH rv32ima
                             LINK_FLAGS -T ${SW}/mig3.ld)
        set(decode_zbb)
    endif()
    dc_add_mainsim_test(design_mig3_decode TOP TbMig3Decode TB tb/tb_mig3_decode.sv
                        FLISTS ${FLISTS}
                        ARGS +hex=${CMAKE_CURRENT_BINARY_DIR}/design_mig3_decode.hex
                             ${decode_zbb})

    # Programs run on TbMig3, built once; tb/tb_mig3.flist has the modules it instantiates.
    cmake_language(CALL dc_add_${SIM}_build design_mig3_sim TOP TbMig3 TB tb/tb_mig3.sv
                   FLISTS ${FLISTS} ${CMAKE_CURRENT_SOURCE_DIR}/tb/tb_mig3.flist)

    # Logs cost a file per test: written only with these options.
    option(DARK_CIRCUIT_MIG3_TRACE "Mig3 program tests write a trace (+trace)" OFF)
    option(DARK_CIRCUIT_MIG3_KANATA "Mig3 program tests write a Konata log (+kanata)" OFF)

    # mig3_program_test(<name> SOURCES <file>... [ARCH <march>] [FLAGS <flag>...]
    #                   [ARGS <arg>...] [LABELS <label>...] [OUTPUT <regex>])
    #
    # Build RISC-V program design_mig3_<name> and add test design_mig3_<name>.<sim>
    # that runs it on TbMig3 with the main simulator; ARGS get +hex=<program hex> and
    # +symbols=<program symbols>, with DARK_CIRCUIT_MIG3_TRACE +trace=<test>.<sim>.trace,
    # with DARK_CIRCUIT_MIG3_KANATA +kanata=<test>.<sim>.kanata, all in the build directory;
    # ARCH is -march of the program (default rv32i);
    # LABELS are added to the tests;
    # with OUTPUT the output (semihosting console) must match <regex>.
    function(mig3_program_test NAME)
        cmake_parse_arguments(P "" "OUTPUT;ARCH" "SOURCES;FLAGS;ARGS;LABELS" ${ARGN})
        if(NOT P_ARCH)
            set(P_ARCH rv32i)
        endif()
        set(prog design_mig3_${NAME})
        dc_add_riscv_program(${prog} SOURCES ${P_SOURCES} ARCH ${P_ARCH} FLAGS ${P_FLAGS}
                             LINK_FLAGS -T ${SW}/mig3.ld)
        set(logs)
        if(DARK_CIRCUIT_MIG3_TRACE)
            list(APPEND logs +trace=${CMAKE_CURRENT_BINARY_DIR}/${prog}.${SIM}.trace)
        endif()
        if(DARK_CIRCUIT_MIG3_KANATA)
            list(APPEND logs +kanata=${CMAKE_CURRENT_BINARY_DIR}/${prog}.${SIM}.kanata)
        endif()
        cmake_language(CALL dc_add_${SIM}_run ${prog} BUILD design_mig3_sim
                       ARGS +hex=${CMAKE_CURRENT_BINARY_DIR}/${prog}.hex
                            +symbols=${CMAKE_CURRENT_BINARY_DIR}/${prog}.sym
                            ${logs} ${P_ARGS}
                       LABELS ${P_LABELS} OUTPUT ${P_OUTPUT})
    endfunction()

    # Fetch: straight-line program, every instruction retires, halt at EBREAK.
    mig3_program_test(fetch SOURCES fetch.S
                      ARGS +expect_sequential +expect_retired=5 +expect_halt_pc=10)

    # ALU program: OP, OP-IMM, LUI, AUIPC execute, registers checked at halt.
    mig3_program_test(alu_prog SOURCES alu.S ARGS +expect_sequential +expect_regs)

    # Branches and jumps: every branch type taken and not taken, JAL, JALR.
    mig3_program_test(branch SOURCES branch.S ARGS +expect_regs)
    # The same with a slow memory: ready withheld, answers after 1 to 3 clocks, now and then
    # 5 to 10; fetch waits.
    mig3_program_test(branch_slow_mem SOURCES branch.S
                      ARGS +expect_regs +mem_latency=70,80,1,3,5,10)

    # Loads and stores: every size and offset, sign extension, strobes.
    mig3_program_test(load_store SOURCES load_store.S ARGS +expect_sequential +expect_regs)
    # The same with a slow memory: ready withheld, words after 1 to 3 clocks, now and then 5
    # to 10; EX and MEM/WB wait.
    mig3_program_test(load_store_slow_mem SOURCES load_store.S
                      ARGS +expect_sequential +expect_regs +mem_latency=70,80,1,3,5,10)

    # Faults trap: a handler checks mcause, mepc and mtval; rd and memory are not
    # written. One build of the program per case (-DCASE_<case>):
    # misaligned jump target, load, store and AMO address (rv32ia: the AMO); ECALL,
    # illegal words, CSR
    # instructions on a missing CSR or writing a read-only one.
    set(FAULT_ARGS +expect_trap +expect_regs +expect_mem_unchanged)
    foreach(case IN ITEMS jalr lw sh amo)
        string(TOUPPER ${case} case_macro)
        mig3_program_test(misaligned_${case} SOURCES misaligned.S ARCH rv32ia
                          FLAGS -DCASE_${case_macro} ARGS ${FAULT_ARGS})
    endforeach()
    foreach(case IN ITEMS ecall zero ones csr_unknown csr_readonly)
        string(TOUPPER ${case} case_macro)
        mig3_program_test(illegal_${case} SOURCES illegal.S FLAGS -DCASE_${case_macro}
                          ARGS ${FAULT_ARGS})
    endforeach()

    # Debug port and resume: the testbench changes a0 at two EBREAKs and resumes.
    mig3_program_test(resume SOURCES resume.S
                      ARGS +resumes=2 +expect_sequential +expect_retired=6
                           +expect_halt_pc=14 +expect_regs)

    # CSRs and counters: Zicsr instructions on mscratch, read-only CSRs, Zicntr. The tests
    # that count cycles (this one, muldiv, branch_id, btb_if, ras_id) and the benchmarks run
    # uncached (+uncached): the caches would add the cycles of their misses.
    # @kb: rtl/design/mig2/caches_in_core
    mig3_program_test(csr SOURCES csr.S ARGS +expect_regs +uncached)

    # M extension: results used right away, division and branches, cycle cost, minstret.
    mig3_program_test(muldiv SOURCES muldiv.S ARCH rv32im ARGS +expect_regs +uncached)

    # LR.W and SC.W (Zalrsc): the reservation of Mig3Atomic in the corners of the pipeline
    # (see lrsc.S); the retire check checks every SC against a reservation of its own.
    mig3_program_test(lrsc SOURCES lrsc.S ARCH rv32ia ARGS +expect_trap +expect_regs)

    # Interrupts: the machine external interrupt (meip) of the testbench's source
    # (TbMig3Irq, +irq_random), taken on chosen instructions (irq.S), and at random places
    # without changing what a program computes (irq_random.S).
    mig3_program_test(irq SOURCES irq.S ARCH rv32ima FLAGS -I${SW}
                      ARGS +expect_trap +expect_regs +irq_random=1)
    mig3_program_test(irq_random SOURCES irq_random.S ARCH rv32ima FLAGS -I${SW}
                      ARGS +expect_trap +expect_regs +irq_random=7 +irq_max_gap=60)
    # The PLIC from software: registers, threshold, a claim acts once.
    mig3_program_test(plic SOURCES plic.S FLAGS -I${SW}
                      ARGS +expect_regs +irq_random=3 +irq_max_gap=1000)
    # The Timer of Mig3Cpu: periodic interrupts through the PLIC, a handler (timer.S).
    mig3_program_test(timer SOURCES timer.S FLAGS -I${SW} ARGS +expect_trap +expect_regs)
    # The drivers sw/riscv/drivers/timer.h and plic.h from C, a C handler (timer_c.c): exit 0
    # when the interrupts came as they should.
    mig3_program_test(timer_c
                      SOURCES ${SW}/crt0.S ${SW}/semihosting/riscv_semihosting.c timer_c.c
                      FLAGS -O2 -Wall -Wextra -ffreestanding -I${SW} -I${SW}/semihosting
                      ARGS +expect_exit=0 +expect_trap)

    # Traps: mtvec, mepc, mstatus through ECALL and MRET, WFI, EBREAK as a breakpoint trap.
    mig3_program_test(trap SOURCES trap.S ARGS +expect_trap +first_ebreak_traps +expect_regs)

    # JAL in the corners of the pipeline: on the wrong path, behind a division, to a
    # misaligned target, after a halting EBREAK, back to back, its link used right away.
    mig3_program_test(jal_id SOURCES jal_id.S ARCH rv32im
                      ARGS +expect_trap +resumes=1 +expect_regs)

    # Conditional branches in the corners of the pipeline: every pair of guess and outcome
    # of a static guess, waiting in ID (load-use, division), on the wrong path, back to back,
    # to misaligned targets. +max_pipeline_cycles is a cycle ceiling on the pipeline cycles
    # (Mig3 README): lower it when a change makes the test faster.
    mig3_program_test(branch_id SOURCES branch_id.S ARCH rv32im
                      ARGS +expect_trap +expect_regs +max_pipeline_cycles=171 +uncached)

    # Jumps and conditional branches that a BTB learns, in the corners of the pipeline:
    # loops, calls, branches taken every time and every other time, two branches sharing an
    # entry, waiting in ID (load-use, division), back to back, a loop of two instructions, on
    # the wrong path, to a misaligned target. With a cycle ceiling (Mig3 README).
    mig3_program_test(btb_if SOURCES btb_if.S ARCH rv32im
                      ARGS +expect_trap +expect_regs +max_pipeline_cycles=506 +uncached)

    # Calls and returns in the corners of the pipeline, for the return-address stack: deep
    # recursion (the stack wraps), an empty function, a return waiting in ID (load-use,
    # division), an indirect call, a return to a changed ra, a call on the wrong path, calls
    # that wait in ID, a swap (coroutine), calls in a trap handler. With a cycle ceiling.
    mig3_program_test(ras_id SOURCES ras_id.S ARCH rv32im
                      ARGS +expect_trap +expect_regs +max_pipeline_cycles=462 +uncached)

    # Semihosting: the C program of test/sw/riscv/semihosting (QEMU) prints and exits
    # with 3 on Mig3 too; crt0.S and the semihosting library of sw/riscv.
    mig3_program_test(semihosting
                      SOURCES ${SW}/crt0.S ${SW}/semihosting/riscv_semihosting.c
                              ${PROJECT_SOURCE_DIR}/test/sw/riscv/semihosting/test_semihosting.c
                      FLAGS -O2 -Wall -Wextra -ffreestanding -I${SW}/semihosting
                      ARGS +expect_exit=3
                      OUTPUT "semihost_write0 works[\r\n]+OK")

    # Semihosting SYS_EXIT (0x18): on RV32 only the reason, in a1; ADP_Stopped_ApplicationExit
    # is exit 0, any other reason exit 1 (the semihosting test uses SYS_EXIT_EXTENDED).
    mig3_program_test(sys_exit SOURCES sys_exit.S FLAGS -DREASON=0x20026 ARGS +expect_exit=0)
    mig3_program_test(sys_exit_error SOURCES sys_exit.S FLAGS -DREASON=0x20023
                      ARGS +expect_exit=1)

    # riscv-tests with their standard environment env/p (source fetched by cmake/fetch.cmake):
    # self-checking, each test ends with a store to tohost. Labels riscv-tests and the suite.
    dc_riscv_tests()
    if(DARK_CIRCUIT_RISCV_TESTS)
        set(RISCV_TESTS ${RISCV_TESTS_DIR})
        set(RISCV_TESTS_FLAGS -I${RISCV_TESTS}/env/p -I${RISCV_TESTS}/isa/macros/scalar)
        set(RISCV_TESTS_ARGS +riscv_test +no_debugger)

        # rv32ui: one test per instruction. Not run: fence_i (writes code into memory; Mig3
        # fetches from a separate instruction memory), ma_data (misaligned loads and stores;
        # Mig3 traps on them).
        foreach(test IN ITEMS simple add addi and andi auipc beq bge bgeu blt bltu bne jal jalr
                              lb lbu lh lhu lw ld_st lui or ori sb sh sw st_ld sll slli slt slti
                              sltiu sltu sra srai srl srli sub xor xori)
            mig3_program_test(rv32ui_${test} SOURCES ${RISCV_TESTS}/isa/rv32ui/${test}.S
                              FLAGS ${RISCV_TESTS_FLAGS} ARGS ${RISCV_TESTS_ARGS}
                              LABELS riscv-tests rv32ui)
        endforeach()

        # rv32mi: machine mode, CSRs, traps. Not run: breakpoint (needs the trigger CSRs of
        # Sdtrig), pmpaddr (needs PMP); both are optional and Mig3 does not have them.
        foreach(test IN ITEMS csr illegal instret_overflow lh-misaligned lw-misaligned ma_addr
                              ma_fetch mcsr sbreak scall sh-misaligned shamt sw-misaligned zicntr)
            mig3_program_test(rv32mi_${test} SOURCES ${RISCV_TESTS}/isa/rv32mi/${test}.S
                              FLAGS ${RISCV_TESTS_FLAGS} ARGS ${RISCV_TESTS_ARGS}
                              LABELS riscv-tests rv32mi)
        endforeach()

        # Benchmarks, with DARK_CIRCUIT_BENCHMARKS only (not regular testing): programs of
        # riscv-tests/benchmarks, unchanged, with sw/riscv/bench: real code with branches and
        # calls, to measure cycles (their own results are not printed; the exit status is
        # their own check). DIR is the directory of the benchmark, REPEAT the runs of its
        # main (BENCH_REPEAT), CEILINGS its ceiling of pipeline cycles per gcc version
        # (Mig3 README, dc_riscv_cycle_ceiling): the pipeline cycles + 1 %, rounded up to 1000
        # (+max_cycles is twice that, a guard against a hang). Lower it when a
        # change makes the benchmark faster; add the version of a new compiler. ARCH is
        # -march (default rv32im); FLAGS come after -O2, so an -O there replaces it. They
        # run uncached (+uncached): the cycles of the pipeline, as before the caches.
        # @kb: test/design/mig2/benchmarks
        if(DARK_CIRCUIT_BENCHMARKS)
            function(mig3_bench_test NAME)
                cmake_parse_arguments(P "" "DIR;REPEAT;ARCH" "SOURCES;FLAGS;CEILINGS" ${ARGN})
                if(NOT P_ARCH)
                    set(P_ARCH rv32im)
                endif()
                dc_riscv_cycle_ceiling(ceiling design_mig3_${NAME} ${P_CEILINGS})
                math(EXPR guard "2 * ${ceiling}")
                mig3_program_test(${NAME}
                                  SOURCES ${SW}/crt0.S ${SW}/semihosting/riscv_semihosting.c
                                          ${SW}/bench/bench.c ${P_SOURCES}
                                  ARCH ${P_ARCH}
                                  FLAGS -O2 -ffreestanding -fno-builtin-printf
                                        -include ${SW}/bench/bench_main.h
                                        -DBENCH_REPEAT=${P_REPEAT}
                                        -I${SW}/bench/include -I${SW}/semihosting -I${P_DIR}
                                        -I${RISCV_TESTS}/benchmarks/common
                                        -I${RISCV_TESTS}/env ${P_FLAGS}
                                  ARGS +expect_exit=0 +max_pipeline_cycles=${ceiling}
                                       +max_cycles=${guard} +uncached
                                  LABELS benchmark)
            endfunction()

            # Dhrystone: one run is 500 loops; 6 runs, about 5 s on Verilator.
            set(DHRY ${RISCV_TESTS}/benchmarks/dhrystone)
            mig3_bench_test(dhrystone DIR ${DHRY} REPEAT 6
                            CEILINGS 12.2.0 1956000
                            SOURCES ${DHRY}/dhrystone.c ${DHRY}/dhrystone_main.c
                            FLAGS -Wno-implicit-int -Wno-implicit-function-declaration)

            # qsort: quicksort of 2048 random numbers, data-dependent branches. One run: the
            # sort is in place, a second run would sort sorted numbers.
            set(QSORT ${RISCV_TESTS}/benchmarks/qsort)
            mig3_bench_test(qsort DIR ${QSORT} REPEAT 1 CEILINGS 12.2.0 168000
                            SOURCES ${QSORT}/qsort_main.c)

            # towers: Towers of Hanoi with 7 discs, recursive: calls and returns. Every run
            # sets up the towers again.
            set(TOWERS ${RISCV_TESTS}/benchmarks/towers)
            mig3_bench_test(towers DIR ${TOWERS} REPEAT 50 CEILINGS 12.2.0 238000
                            SOURCES ${TOWERS}/towers_main.c)

            # CoreMark (EEMBC): list processing, matrix, state machine, CRC; its standard
            # performance run (seeds 0, 0, 0x66, 2000 bytes), fetched unchanged, with the
            # port sw/riscv/coremark: ticks are cycles, the exit status is the check of its
            # CRCs, it prints CoreMark/MHz. Simulated: far shorter than a valid score's 10 s.
            # Three builds of the one source, each a different load on the CPU: coremark
            # (-O2), code as usually compiled, the regression ceiling; coremark_tuned (the
            # flags of published RISC-V scores, Zbb), unrolled and inlined, code far larger
            # than the I-cache, the score to compare with other cores; coremark_O0 (-O0),
            # every variable on the stack, a load or store in most instructions (load-use).
            # @kb: test/design/mig3/coremark
            dc_coremark()
            if(DARK_CIRCUIT_COREMARK)
                set(CM ${COREMARK_DIR})
                function(mig3_coremark NAME)
                    cmake_parse_arguments(C "" "ITERATIONS;CEILING;ARCH" "FLAGS" ${ARGN})
                    mig3_bench_test(${NAME} DIR ${CM} REPEAT 1 CEILINGS 12.2.0 ${C_CEILING}
                                    ARCH ${C_ARCH}
                                    SOURCES ${CM}/core_list_join.c ${CM}/core_main.c
                                            ${CM}/core_matrix.c ${CM}/core_state.c
                                            ${CM}/core_util.c ${SW}/coremark/core_portme.c
                                    FLAGS -I${SW}/coremark -DITERATIONS=${C_ITERATIONS}
                                          ${C_FLAGS})
                endfunction()

                mig3_coremark(coremark ITERATIONS 5 CEILING 1820000)
                if(DARK_CIRCUIT_RISCV_ZBB)
                    mig3_coremark(coremark_tuned ITERATIONS 5 CEILING 1407000
                                  ARCH rv32im_zbb
                                  FLAGS -funroll-all-loops -finline-limit=600
                                        -ftree-dominator-opts -fno-if-conversion2
                                        -fselective-scheduling -fno-code-hoisting
                                        -falign-functions=4 -falign-jumps=4 -falign-loops=4)
                endif()
                mig3_coremark(coremark_O0 ITERATIONS 1 CEILING 1537000 FLAGS -O0)
            endif()
        endif()

        # rv32um: multiply and divide.
        foreach(test IN ITEMS mul mulh mulhsu mulhu div divu rem remu)
            mig3_program_test(rv32um_${test} SOURCES ${RISCV_TESTS}/isa/rv32um/${test}.S
                              ARCH rv32im FLAGS ${RISCV_TESTS_FLAGS} ARGS ${RISCV_TESTS_ARGS}
                              LABELS riscv-tests rv32um)
        endforeach()

        # rv32ua: the A extension, LR/SC and the AMOs (done in front of the memory,
        # AtomicUnit in Mig3Cpu: kb rtl/design/mig3/amo).
        foreach(test IN ITEMS amoadd_w amoand_w amomax_w amomaxu_w amomin_w amominu_w
                              amoor_w amoswap_w amoxor_w lrsc)
            mig3_program_test(rv32ua_${test} SOURCES ${RISCV_TESTS}/isa/rv32ua/${test}.S
                              ARCH rv32ima FLAGS ${RISCV_TESTS_FLAGS} ARGS ${RISCV_TESTS_ARGS}
                              LABELS riscv-tests rv32ua)
        endforeach()

        # rv32uzbb: Zbb, the groups done so far; only when the compiler knows Zbb.
        if(DARK_CIRCUIT_RISCV_ZBB)
            foreach(test IN ITEMS andn orn xnor min minu max maxu rol ror rori
                                  sext_b sext_h zext_h orc_b rev8 clz ctz cpop)
                mig3_program_test(rv32uzbb_${test} SOURCES ${RISCV_TESTS}/isa/rv32uzbb/${test}.S
                                  ARCH rv32i_zbb FLAGS ${RISCV_TESTS_FLAGS}
                                  ARGS ${RISCV_TESTS_ARGS} LABELS riscv-tests rv32uzbb)
            endforeach()
        else()
            message(STATUS "Mig3: the RISC-V compiler does not know Zbb: rv32uzbb not run")
        endif()
    endif()
endif()
