# Mig1: RV32I RISC-V CPU

Mig1 is a small RISC-V CPU: RV32IM (base integer instructions, multiply and divide),
Zicsr (CSR instructions) and Zicntr (counters), machine-mode traps; no interrupts.
It passes riscv-tests rv32ui (40 of 42 tests), rv32um (8 of 8) and rv32mi (14 of 16) with
their standard environment; the other tests need features Mig1 does not have, see Testing.

- 3-stage pipeline: IF (fetch) | ID (decode, register read) | EX (everything else),
  interlock instead of forwarding; on the way to 5 stages, step by step (see CPI).
- Harvard: instruction memory and data memory, both with 1 clock read latency
  (like SRAM and FPGA block RAM). Mig1Cpu loads the same program image into both.
- Faults trap to mtvec (machine mode), MRET returns. With a debugger attached, EBREAK
  halts the core and the debugger resumes it.
- Runs C programs with semihosting (print, exit code): the same binary code as on QEMU.
- Retire trace of every retired instruction in RVFI form (riscv-formal), for testbenches.

RTL is in this directory, configuration in `cfg/`, tests in `test/design/mig1/`.

## Files

| File | What |
|------|------|
| `mig1_pkg.sv` | Mig1Pkg: widths, port and boundary structs, kind_t, decoded_t |
| `mig1_config_pkg.sv` | Mig1ConfigPkg, generated from `cfg/mig1_config.yaml` |
| `mig1_fetch.sv`, `mig1_control.sv`, `mig1_decode.sv`, `mig1_regs.sv`, `mig1_alu.sv`, `mig1_branch.sv`, `mig1_lsu.sv`, `mig1_csr.sv`, `mig1_muldiv.sv` | the parts |
| `mig1_pipe.sv` | Mig1Pipe: the pipeline registers (ID/EX) |
| `mig1_core.sv` | Mig1Core: connects the parts, synthesizable, memories are outside |
| `mig1_cpu.sv` | Mig1Cpu: Mig1Core with SimROM (imem) and SimRAM (dmem), for simulation |
| `mig1.flist` | files in compile order |

## Parts and dataflow

```
IF  Mig1Fetch (PC) --imem_req--> imem
                                   | 1 clock
ID  imem_rsp -> id_insn -> Mig1Decode -> id_dec
    id_dec -> Mig1Regs -> rs1 data, rs2 data
    id_ex_d = {valid, pc, insn, id_dec, rs1 data, rs2 data} -> Mig1Pipe
                                   | 1 clock
EX  id_ex_q -> ex_insn, ex_dec, rs1, rs2, pc
    rs1, rs2, imm, pc -> Mig1Alu    -> ALU result: rd value, or address of load/store
                      -> Mig1Branch -> branch (taken, target, misaligned), link = pc + 4
    address, rs2      -> Mig1Lsu    -> dmem_req; 1 clock later dmem_rsp -> load data
                                       lsu (stall, misaligned)
    ex_dec, rs1       -> Mig1Csr    -> old CSR value; CSR write when the instruction completes
    rs1, rs2          -> Mig1MulDiv -> product (1 cycle) or quotient/remainder (34 cycles,
                                       muldiv stall)
    rd value = ALU result | link | load data | CSR value | M result, chosen by ex_dec.rd_src;
               Mig1Regs writes it when ex_done=1
    id_dec, ex_dec, branch, lsu, CSR fault, muldiv stall -> Mig1Control
        -> if_ctrl (run, stall, redirect, target) -> Mig1Fetch
        -> pipe_ctrl (ex_stall, ex_flush) -> Mig1Pipe
        -> ex_done, ex_trap (to Mig1Csr), halt, halt_pc
```

Mig1Core only connects parts; its signals have the prefix of their stage (`if_`, `id_`,
`ex_`).
Each part works on "the instruction in its stage" and does not know which stage that
is, so the same parts fit a 5-stage pipeline.

| Part        | Stage | Does |
|-------------|-------|------|
| Mig1Fetch   | IF    | PC (PrgCounter), imem request; holds on stall, jumps on redirect and reset |
| Mig1Control | -     | run, stalls, flushes, interlock, redirect, traps (cause, mtval), halt, resume; ex_done: the instruction completes |
| Mig1Pipe    | -     | pipeline registers: bubble on reset or flush, hold on stall |
| Mig1Decode  | ID    | instruction -> decoded_t: kind, registers, funct3, alt, immediate, controls |
| Mig1Regs    | ID    | x0..x31, 2 reads (ID) + 1 write (EX); the debug port owns read port 0 and the write port while halted |
| Mig1Alu     | EX    | rd value of OP, OP-IMM, LUI, AUIPC; address rs1 + imm of loads and stores |
| Mig1Branch  | EX    | taken, target, misaligned target; link = pc + 4 for JAL, JALR |
| Mig1Lsu     | EX    | dmem requests, store strobes, load data extension, misaligned address, load stall |
| Mig1Csr     | EX    | CSRs, counters, trap CSRs; CSR instructions read the old value and write the new one |
| Mig1MulDiv  | EX    | M extension: Int32Mul (combinational), Int32Div (32 clocks, stalls), RISC-V results of divide by 0 and overflow |

Boundary structs are in Mig1Pkg, named by their producer: `fetch_t`, `fetch_ctrl_t`,
`pipe_ctrl_t`, `decoded_t`, `branch_t`, `lsu_t`; pipeline registers by their boundary:
`id_ex_t`; memory and debug ports are `<group>_req_t`/`_rsp_t`.
Decode gives controls (`rd_we`, `rd_src`, `uses_rs1`, `uses_rs2`); units derive their
operation from `kind`, `funct3` and `alt` (RiscvPkg `F3_*` names the funct3 values).

## Pipeline timing

Every instruction takes one cycle in each stage, plus:

| Case | Extra cycles | Why |
|------|--------------|-----|
| taken branch, JAL, JALR; trap, MRET | 2 | decided in EX; the instructions in ID and IF are dropped (two bubbles) |
| uses rd of the instruction before it | 1 | interlock: ID reads registers, EX writes them at the end of its cycle |
| load | 1 | data comes 1 clock after the read request; the load waits in EX |
| store | 0 | written in its cycle in EX |
| multiply | 0 | Int32Mul is combinational |
| divide, remainder | 33 | Int32Div takes 32 clocks; start, 32 steps, then the result |

A load whose rd the next instruction uses costs 2: the load waits in EX, then the
interlock. Measured: branch.S retires 58 instructions in 111 cycles, load_store.S 43 in 71.

```
straight-line         b uses rd of a           taken branch B -> T
cycle  1  2  3  4     cycle  1  2  3     4  5   cycle  1   2    3    4  5    6
IF     a  b  c  d     IF     a  b  hold  c  d   IF     B   B+4  B+8  T  T+4  T+8
ID        a  b  c     ID        a  b     b  c   ID         B    B+4  -  T    T+4
EX           a  b     EX           a     -  b   EX              B    -  -    T

load L, U uses rd of L
cycle  1  2  3      4      5    6
IF     L  U  hold   hold   U+4  U+8
ID        L  U      U      U    U+4
EX           L 1st  L 2nd  -    U
dmem         read   data
```

- Redirect: Mig1Branch decides in EX; Mig1Control redirects fetch to the target, flushes
  ID (EX gets a bubble) and the instruction requested in the same cycle comes back with
  `fetch.valid=0`.
- Stall: while a load or a division waits in EX, Mig1Pipe keeps it and fetch holds
  everything (PC, imem output, fetch), so ID keeps its instruction too.
- Interlock: when the instruction in ID reads a register that the instruction in EX
  writes, fetch holds and EX gets a bubble; the next cycle ID reads the new value.
- Halt: EBREAK halts in EX and flushes ID; resume redirects fetch to `halt_pc + 4`.

## CSRs

CSR instructions (Zicsr: CSRRW, CSRRS, CSRRC and their immediate forms) read the old
value into rd and write the new one when they complete; CSRRS and CSRRC with rs1 = x0
(immediate 0) do not write, so `csrr` reads read-only CSRs. Addresses come from
RiscvCsrPkg (generated from riscv-opcodes, like the encodings).

| CSR | Access | Value |
|---|---|---|
| `mcycle`, `mcycleh` | read/write | clock cycles since reset, 64-bit |
| `minstret`, `minstreth` | read/write | instructions completed (traps do not count), 64-bit |
| `cycle`, `instret` (and `h`) | read | Zicntr: the same counters |
| `time`, `timeh` | read | the cycle counter: Mig1 has no real-time clock |
| `mscratch` | read/write | scratch word |
| `mstatus` | MIE, MPIE read/write | MPP reads 3 (machine mode only), other bits 0; `mstatush` reads 0 |
| `mtvec` | read/write | trap handler address; direct mode only, bits 1:0 read 0 |
| `mepc`, `mcause`, `mtval` | read/write | set by traps; `mepc` bits 1:0 read 0 |
| `mie`, `mip` | read 0, writes ignored | no interrupts |
| `misa` | read, writes ignored | `0x40001100`: RV32IM |
| `mvendorid`, `marchid`, `mimpid`, `mhartid` | read | 0 |

A CSR write wins over the count of its cycle: the next read gives the written value.
A CSR instruction that reads instret sees the count before itself.

## Traps, halt and debug

A fault of the instruction in EX is a trap (machine mode): the instruction writes
nothing, retires with `trap=1` (minstret does not count it), and fetch continues at
`mtvec`; `mepc` is its address, `mcause` and `mtval` tell why, `mstatus.MPIE` gets MIE
and MIE gets 0. MRET returns to `mepc` (MIE gets MPIE, MPIE gets 1). WFI is a no-op.

| Fault | `mcause` | `mtval` |
|---|---|---|
| taken jump/branch to an address not divisible by 4 | 0 misaligned fetch | the target |
| illegal encoding; CSR instruction on a CSR Mig1 does not have, or writing a read-only CSR | 2 illegal instruction | the instruction |
| EBREAK when no debugger is attached (`ebreak_halt=0`) | 3 breakpoint | its address |
| load / store with misaligned address | 4 / 6 misaligned load / store | the address |
| ECALL | 11 environment call from M-mode | 0 |

EBREAK halts the core instead when the debugger sets `dbg_req.ebreak_halt` (like
`dcsr.ebreakm` of the debug spec): it completes, `halt=1`, `halt_pc` is its address,
nothing is in flight. While halted, the debug port (`dbg_req_t`, `dbg_rsp_t`) reads a
register (combinational) and writes one per clock; `resume` for one clock continues at
`halt_pc + 4`. TbMig1 is attached as debugger (`ebreak_halt=1`), so programs end with
EBREAK; semihosting uses that too.

## Semihosting

Programs print and exit through RISC-V semihosting, like on QEMU: `sw/riscv/crt0.S`
calls `main` and passes its return value to `semihost_exit`, `sw/riscv/semihosting/`
has the calls. A call is the sequence `slli x0,x0,0x1f` / `ebreak` / `srai x0,x0,7`
with the operation in a0 and its argument in a1. The core simply halts at the EBREAK;
the host (TbMig1) recognizes the sequence around halt_pc, reads a0 and a1 through the
debug port and memory with `peek()`, does the call and resumes the core, which
continues with the `srai` no-op. Supported: SYS_WRITEC, SYS_WRITE0 (print to stdout),
SYS_EXIT, SYS_EXIT_EXTENDED (end with an exit status).

Link programs with `sw/riscv/mig1.ld` (with `sw/riscv/qemu_virt.ld` for QEMU).

## Retire trace

`retire` (`retire_t` in Mig1Pkg) has one entry per retired instruction, with the fields
and names of RVFI, the interface of riscv-formal; fields an instruction does not use
are 0. Unlike the other ports, its addresses are byte addresses, as in RVFI.

| Field | Meaning |
|---|---|
| `valid`, `order` | an instruction retires; its index 0, 1, 2, ... |
| `insn`, `trap` | the instruction; 1 when it faulted (it writes nothing, the core halts) |
| `pc_rdata`, `pc_wdata` | its address and the address of the next instruction |
| `rs1_addr`, `rs1_rdata`, `rs2_addr`, `rs2_rdata` | registers read and their values |
| `rd_addr`, `rd_wdata` | register written and the value (0 for none and for x0) |
| `mem_addr`, `mem_rmask`, `mem_wmask`, `mem_rdata`, `mem_wdata` | load/store: word address, bytes read/written, data words ("aligned memory" of RVFI) |

Not in the struct, constant for Mig1: `intr`=0, `mode`=3 (machine), `ixl`=1 (32-bit).
TbMig1 checks every entry against the program and its own copy of the registers:
instruction words, control flow (`pc_wdata` of one is `pc_rdata` of the next), registers
read, the address and bytes of loads and stores, memory after stores, traps; and writes
the trace to `<test>.<simulator>.trace`.

## Configuration

`cfg/mig1_config.yaml`: reset address (0) and memory size (64 KiB each).
`make config` generates `mig1_config_pkg.sv`, the linker script `sw/riscv/mig1.ld` and
`sw/riscv/mig1_config.h`; test `design_mig1.config` fails when they are out of date.

## Testing

| Tests | What |
|-------|------|
| `design_mig1_decode`, `_regs`, `_alu`, `_mem` | unit tests with their own testbenches |
| `fetch`, `alu_prog`, `branch`, `load_store`, `resume` | programs on TbMig1, registers checked at the end |
| `semihosting` | C program of `test/sw/riscv/semihosting` (also run on QEMU): output and exit code 3 |
| `csr` | CSR instructions on mscratch, read-only CSRs, counters |
| `muldiv` | M results used right away, division and branches, a division in a dropped slot, cycles and minstret of a division |
| `trap` | mtvec, mepc, mstatus through ECALL and MRET, WFI, EBREAK as a breakpoint trap |
| `misaligned_{jalr,lw,sh}`, `illegal_{ecall,zero,ones,csr_unknown,csr_readonly}` | faults: a handler checks mcause, mepc, mtval; nothing written |
| `rv32ui_*`, `rv32um_*`, `rv32mi_*` (labels `riscv-tests` and the suite) | riscv-tests with their standard environment `env/p`; end with a store to `tohost` |

Not run from rv32ui: fence_i (writes code into memory, Mig1 fetches from a separate
instruction memory) and ma_data (misaligned loads and stores, Mig1 traps on them).
Not run from rv32mi: breakpoint (needs the trigger CSRs of Sdtrig) and pmpaddr (needs
PMP); both are optional extensions Mig1 does not have.

All run on Icarus (4-state: X in retire fails) and Verilator. TbMig1 is built once per
simulator; its plusargs (`+expect_regs`, `+resumes`, `+riscv_test`, ...) are explained
at the top of `tb_mig1.sv`. Run: `make run R=mig1`, `make run L=riscv-tests`; `V=1` shows
the paths of trace files.

## CPI

Cycles of every program at each step of the pipeline, measured with TbMig1 (Verilator;
Icarus gives the same): instructions retired and cycles from reset to the halt (or the
store to `tohost` of riscv-tests, environment startup included). CPI is cycles per
instruction.

- 2-stage: IF | EX, before the 5-stage work, 2026-10-18.
- 3-stage (5a): IF | ID | EX with interlock, 2026-10-18. Redirects cost 2 bubbles
  instead of 1, an instruction that uses the rd of the one before it waits 1 cycle.

| Programs | Count | Instructions | 2-stage cycles | CPI | 3-stage cycles | CPI |
|---|---|---|---|---|---|---|
| own programs (`test/design/mig1/*.S`, semihosting) | 17 | 421 | 655 | 1.56 | 822 | 1.95 |
| riscv-tests rv32ui | 40 | 14722 | 16111 | 1.09 | 21758 | 1.48 |
| riscv-tests rv32um | 8 | 2549 | 3885 | 1.52 | 4778 | 1.87 |
| riscv-tests rv32mi | 14 | 2112 | 2373 | 1.12 | 3305 | 1.56 |

<details><summary>Every program</summary>

| Program | Instructions | 2-stage cycles | CPI | 3-stage cycles | CPI |
|---|---|---|---|---|---|
| `alu_prog` | 28 | 29 | 1.04 | 32 | 1.14 |
| `branch` | 58 | 78 | 1.34 | 111 | 1.91 |
| `csr` | 39 | 40 | 1.03 | 52 | 1.33 |
| `fetch` | 5 | 6 | 1.20 | 9 | 1.80 |
| `illegal_csr_readonly` | 13 | 16 | 1.23 | 23 | 1.77 |
| `illegal_csr_unknown` | 13 | 16 | 1.23 | 23 | 1.77 |
| `illegal_ecall` | 11 | 13 | 1.18 | 18 | 1.64 |
| `illegal_ones` | 13 | 16 | 1.23 | 23 | 1.77 |
| `illegal_zero` | 13 | 16 | 1.23 | 23 | 1.77 |
| `load_store` | 43 | 64 | 1.49 | 71 | 1.65 |
| `misaligned_jalr` | 13 | 15 | 1.15 | 22 | 1.69 |
| `misaligned_lw` | 13 | 15 | 1.15 | 22 | 1.69 |
| `misaligned_sh` | 13 | 15 | 1.15 | 22 | 1.69 |
| `muldiv` | 21 | 156 | 7.43 | 164 | 7.81 |
| `resume` | 6 | 13 | 2.17 | 16 | 2.67 |
| `rv32mi_csr` | 168 | 180 | 1.07 | 251 | 1.49 |
| `rv32mi_illegal` | 120 | 137 | 1.14 | 194 | 1.62 |
| `rv32mi_instret_overflow` | 108 | 120 | 1.11 | 162 | 1.50 |
| `rv32mi_lh-misaligned` | 117 | 132 | 1.13 | 182 | 1.56 |
| `rv32mi_lw-misaligned` | 175 | 196 | 1.12 | 280 | 1.60 |
| `rv32mi_ma_addr` | 316 | 372 | 1.18 | 524 | 1.66 |
| `rv32mi_ma_fetch` | 237 | 267 | 1.13 | 385 | 1.62 |
| `rv32mi_mcsr` | 101 | 112 | 1.11 | 151 | 1.50 |
| `rv32mi_sbreak` | 109 | 123 | 1.13 | 170 | 1.56 |
| `rv32mi_scall` | 98 | 109 | 1.11 | 152 | 1.55 |
| `rv32mi_sh-misaligned` | 125 | 141 | 1.13 | 194 | 1.55 |
| `rv32mi_shamt` | 109 | 122 | 1.12 | 168 | 1.54 |
| `rv32mi_sw-misaligned` | 179 | 201 | 1.12 | 280 | 1.56 |
| `rv32mi_zicntr` | 150 | 161 | 1.07 | 212 | 1.41 |
| `rv32ui_add` | 506 | 532 | 1.05 | 700 | 1.38 |
| `rv32ui_addi` | 283 | 300 | 1.06 | 411 | 1.45 |
| `rv32ui_and` | 526 | 552 | 1.05 | 784 | 1.49 |
| `rv32ui_andi` | 239 | 256 | 1.07 | 356 | 1.49 |
| `rv32ui_auipc` | 99 | 112 | 1.13 | 153 | 1.55 |
| `rv32ui_beq` | 332 | 369 | 1.11 | 473 | 1.42 |
| `rv32ui_bge` | 350 | 396 | 1.13 | 513 | 1.47 |
| `rv32ui_bgeu` | 375 | 421 | 1.12 | 563 | 1.50 |
| `rv32ui_blt` | 332 | 369 | 1.11 | 474 | 1.43 |
| `rv32ui_bltu` | 357 | 394 | 1.10 | 524 | 1.47 |
| `rv32ui_bne` | 332 | 371 | 1.12 | 478 | 1.44 |
| `rv32ui_jal` | 96 | 109 | 1.14 | 148 | 1.54 |
| `rv32ui_jalr` | 156 | 179 | 1.15 | 251 | 1.61 |
| `rv32ui_lb` | 270 | 311 | 1.15 | 410 | 1.52 |
| `rv32ui_lbu` | 270 | 311 | 1.15 | 410 | 1.52 |
| `rv32ui_ld_st` | 1005 | 1209 | 1.20 | 1681 | 1.67 |
| `rv32ui_lh` | 286 | 327 | 1.14 | 442 | 1.55 |
| `rv32ui_lhu` | 295 | 336 | 1.14 | 460 | 1.56 |
| `rv32ui_lui` | 106 | 117 | 1.10 | 158 | 1.49 |
| `rv32ui_lw` | 300 | 341 | 1.14 | 470 | 1.57 |
| `rv32ui_or` | 529 | 555 | 1.05 | 790 | 1.49 |
| `rv32ui_ori` | 246 | 263 | 1.07 | 370 | 1.50 |
| `rv32ui_sb` | 459 | 524 | 1.14 | 663 | 1.44 |
| `rv32ui_sh` | 512 | 577 | 1.13 | 769 | 1.50 |
| `rv32ui_simple` | 82 | 92 | 1.12 | 124 | 1.51 |
| `rv32ui_sll` | 534 | 560 | 1.05 | 740 | 1.39 |
| `rv32ui_slli` | 282 | 299 | 1.06 | 409 | 1.45 |
| `rv32ui_slt` | 500 | 526 | 1.05 | 688 | 1.38 |
| `rv32ui_slti` | 278 | 295 | 1.06 | 401 | 1.44 |
| `rv32ui_sltiu` | 278 | 295 | 1.06 | 401 | 1.44 |
| `rv32ui_sltu` | 500 | 526 | 1.05 | 688 | 1.38 |
| `rv32ui_sra` | 553 | 579 | 1.05 | 774 | 1.40 |
| `rv32ui_srai` | 297 | 314 | 1.06 | 439 | 1.48 |
| `rv32ui_srl` | 547 | 573 | 1.05 | 762 | 1.39 |
| `rv32ui_srli` | 291 | 308 | 1.06 | 427 | 1.47 |
| `rv32ui_st_ld` | 525 | 585 | 1.11 | 817 | 1.56 |
| `rv32ui_sub` | 498 | 524 | 1.05 | 688 | 1.38 |
| `rv32ui_sw` | 520 | 585 | 1.12 | 787 | 1.51 |
| `rv32ui_xor` | 528 | 554 | 1.05 | 788 | 1.49 |
| `rv32ui_xori` | 248 | 265 | 1.07 | 374 | 1.51 |
| `rv32um_div` | 137 | 445 | 3.25 | 496 | 3.62 |
| `rv32um_divu` | 138 | 446 | 3.23 | 498 | 3.61 |
| `rv32um_mul` | 500 | 526 | 1.05 | 692 | 1.38 |
| `rv32um_mulh` | 500 | 526 | 1.05 | 700 | 1.40 |
| `rv32um_mulhsu` | 500 | 526 | 1.05 | 700 | 1.40 |
| `rv32um_mulhu` | 500 | 526 | 1.05 | 700 | 1.40 |
| `rv32um_rem` | 137 | 445 | 3.25 | 496 | 3.62 |
| `rv32um_remu` | 137 | 445 | 3.25 | 496 | 3.62 |
| `semihosting` | 76 | 99 | 1.30 | 123 | 1.62 |
| `trap` | 43 | 48 | 1.12 | 68 | 1.58 |

</details>

## Known limits

- Reset does not block a store or a register write of the instruction in EX in that cycle.
- A load of memory outside the program image is X on Icarus (test fails) and 0 on Verilator.

## Next

5-stage pipeline, step by step, CPI measured at each step: MEM (5b), WB as the commit
point (5c), forwarding (5d). Spike cosim (lockstep) starts with Mig2.
