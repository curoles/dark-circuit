# Mig1: RISC-V CPU

Mig1 is a small RISC-V CPU: RV32IM (base integer instructions, multiply and divide),
Zicsr (CSR instructions) and Zicntr (counters), machine-mode traps; no interrupts.
It passes riscv-tests rv32ui (40 of 42 tests), rv32um (8 of 8) and rv32mi (14 of 16) with
their standard environment; the other tests need features Mig1 does not have, see Testing.

- 4-stage pipeline: IF (fetch) | ID (decode, register read, forwarding) | EX (execute;
  branches, traps, CSRs, stores) | MEM/WB (load data, register write, retire). Results
  are forwarded to ID; a load whose rd the next instruction uses costs 1 cycle.
- Harvard: instruction memory and data memory, both with 1 clock read latency
  (like SRAM and FPGA block RAM). Mig1Cpu loads the same program image into both.
- Faults trap to mtvec (machine mode), MRET returns. With a debugger attached, EBREAK
  halts the core and the debugger resumes it.
- Runs C programs with semihosting (print, exit code): the same binary code as on QEMU.
- Retire trace of every retired instruction in RVFI form (riscv-formal), for testbenches.
- Synthesizable: Mig1Core converts with sv2v and maps with Yosys, 5.4 ns in sky130 (see
  Area and speed).

RTL is in this directory, configuration in `cfg/`, tests in `test/design/mig1/`.

Mig1 is the small, simple core of the project; Mig2 (`rtl/design/mig2`) is where bigger
changes go first. On 2026-10-23 Mig1 took over the code of Mig2, which had started as its
copy on 2026-10-19: typed ports and package types, a configuration struct, controls per
part from decode, assertions, and the faster struct library (Wallace-tree multiplier,
Kogge-Stone adders). The pipeline did not change: every program takes the same cycles.

## Files

| File | What |
|------|------|
| `mig1_pkg.sv` | Mig1Pkg: constants and types: ports of Mig1Core, signals between the parts, decode controls, pipeline registers |
| `mig1_config_pkg.sv` | Mig1ConfigPkg: struct `mig1_cfg_t` and its default `MIG1_CFG`, generated from `cfg/mig1_config.yaml` |
| `mig1_fetch.sv`, `mig1_control.sv`, `mig1_decode.sv`, `mig1_regs.sv`, `mig1_forward.sv`, `mig1_alu.sv`, `mig1_branch.sv`, `mig1_lsu.sv`, `mig1_load_data.sv`, `mig1_csr.sv`, `mig1_muldiv.sv` | the parts |
| `mig1_pipe_reg.sv` | Mig1PipeReg: one pipeline register, `parameter type T` (the struct of its boundary) |
| `mig1_pipe.sv` | Mig1Pipe: the pipeline registers ID/EX and EX/MEM (IF/ID is in Mig1Fetch) |
| `mig1_core.sv` | Mig1Core: connects the parts, synthesizable, memories are outside |
| `mig1_cpu.sv` | Mig1Cpu: Mig1Core with SimROM (imem) and SimRAM (dmem), for simulation |
| `mig1.flist` | files in compile order |

## Parts and dataflow

```
IF  Mig1Fetch (PC) --imem_req--> imem
                                   | 1 clock
ID  imem_rsp -> id_insn -> Mig1Decode -> id_dec
    id_dec -> Mig1Regs -> register file values
           -> Mig1Forward (with EX result, MEM/WB result) -> rs1 data, rs2 data
    id_ex_d = {valid, pc, insn, id_dec, rs1 data, rs2 data} -> Mig1Pipe
                                   | 1 clock
EX  id_ex_q -> ex_insn, ex_dec, rs1, rs2, pc
    rs1, rs2, imm, pc -> Mig1Alu    -> ALU result: rd value, or address of load/store
                      -> Mig1Branch -> branch (taken, target, misaligned), link = pc + 4
    address, rs2      -> Mig1Lsu    -> dmem_req: store written now, load read sent;
                                       misaligned
    ex_dec, rs1       -> Mig1Csr    -> old CSR value; CSR write when the instruction completes
    rs1, rs2          -> Mig1MulDiv -> product (1 cycle) or quotient/remainder (34 cycles,
                                       muldiv stall)
    rd value = ALU result | link | CSR value | M result, chosen by ex_dec.rd_src;
               also to Mig1Forward
    ex_mem_d = {retire entry, load, funct3, offset} -> Mig1Pipe
                                   | 1 clock
MEM/WB  ex_mem_q; dmem_rsp -> Mig1LoadData -> load data
    rd value = load data (loads) or the value from EX; Mig1Regs writes it,
               Mig1Forward gets it; retire

id_dec, ex_dec, branch, misaligned, CSR fault, muldiv stall -> Mig1Control
    -> if_ctrl (run, stall, redirect, target) -> Mig1Fetch
    -> pipe_ctrl (ex_stall, ex_flush) -> Mig1Pipe
    -> ex_done, ex_trap (to Mig1Csr), halt, halt_pc
```

Mig1Core only connects parts; its signals have the prefix of their stage (`if_`, `id_`,
`ex_`, `mem_`).
Each part works on "the instruction in its stage" and does not know which stage that
is, so the same parts fit a 5-stage pipeline.

| Part         | Stage  | Does |
|--------------|--------|------|
| Mig1Fetch    | IF     | PC (PrgCounter), imem request; holds on stall, jumps on redirect and reset |
| Mig1Control  | -      | run, stalls, flushes, load-use interlock, redirect, traps (cause, mtval), halt, resume; ex_done: the instruction completes |
| Mig1Pipe     | -      | pipeline registers (Mig1PipeReg): bubble on reset or flush (only valid is cleared), hold on stall |
| Mig1Decode   | ID     | instruction -> decoded_t: kind, registers, funct3, alt, immediate, controls |
| Mig1Regs     | ID     | x0..x31, 2 reads (ID) + 1 write (MEM/WB); the debug port owns read port 0 and the write port while halted |
| Mig1Forward  | ID     | rs1/rs2 values: the youngest of EX result, MEM/WB result, register file |
| Mig1Alu      | EX     | rd value of OP, OP-IMM, LUI, AUIPC; address rs1 + imm of loads and stores |
| Mig1Branch   | EX     | taken, target, misaligned target; link = pc + 4 for JAL, JALR |
| Mig1Lsu      | EX     | dmem requests, store strobes, misaligned address |
| Mig1Csr      | EX     | CSRs, counters, trap CSRs; CSR instructions read the old value and write the new one |
| Mig1MulDiv   | EX     | M extension: Int32Mul (combinational), Int32Div (32 clocks, stalls), RISC-V results of divide by 0 and overflow |
| Mig1LoadData | MEM/WB | loaded value from the dmem word: bytes at the offset, sign/zero extension |

Boundary structs are in Mig1Pkg, named by their producer: `fetch_t`, `fetch_ctrl_t`,
`pipe_ctrl_t`, `decoded_t`, `branch_t`, `trap_t`, `csr_t`, `lsu_mem_t`; pipeline
registers by their boundary: `id_ex_t`, `ex_mem_t`; memory and debug ports are
`<group>_req_t`/`_rsp_t`. Ports use package types (`word_t`, `insn_t`, `iaddr_t`,
`reg_id_t`), not bit ranges.
Decode computes the controls once (`rd_we`, `rd_src`, `uses_rs1`, `uses_rs2`, and one
group per part: `alu`, `br`, `mem`, `sys`, `muldiv`); later stages read them and do not
decode again. Where funct3 selects the operation (ALU operation, branch compare,
load/store size, CSR operation) the part reads `funct3` and `alt` (RiscvPkg `F3_*` names
the funct3 values).

## Pipeline timing

Every instruction takes one cycle in each stage, plus:

| Case | Extra cycles | Why |
|------|--------------|-----|
| taken branch, JAL, JALR; trap, MRET | 2 | decided in EX; the instructions in ID and IF are dropped |
| load whose rd the next instruction uses | 1 | load-use: the data arrives in MEM/WB, then it is forwarded |
| other uses of a result | 0 | forwarded to ID from EX or MEM/WB |
| load, store | 0 | the read is sent / the store written in EX; load data in MEM/WB |
| multiply | 0 | Int32Mul is combinational |
| divide, remainder | 33 | Int32Div takes 32 clocks; start, 32 steps, then the result |

Measured: branch.S retires 58 instructions in 99 cycles, load_store.S 43 in 48.

```
straight-line (also with forwarded results)   load L, U uses rd of L
cycle   1  2  3  4  5                        cycle   1  2  3     4     5    6
IF      a  b  c  d  e                        IF      L  U  hold  U+4   U+8  U+12
ID         a  b  c  d                        ID         L  U     U     U+4  U+8
EX            a  b  c                        EX            L     -     U    U+4
MEM/WB           a  b                        MEM/WB           L     -     U
                                             dmem          read  data

taken branch B -> T
cycle   1   2    3    4   5    6
IF      B   B+4  B+8  T   T+4  T+8
ID          B    B+4  -   T    T+4
EX               B    -   -    T
MEM/WB                B   -    -
```

- Redirect: Mig1Branch decides in EX; Mig1Control redirects fetch to the target, flushes
  ID (EX gets a bubble) and the instruction requested in the same cycle comes back with
  `fetch.valid=0`.
- Stall: while a division waits in EX, Mig1Pipe keeps it and fetch holds everything
  (PC, imem output, fetch); MEM/WB gets bubbles.
- Forwarding: Mig1Forward gives ID the value of the youngest instruction that writes the
  register: EX, else MEM/WB, else the register file. The value goes into the ID/EX
  register, so the retire trace shows it and TbMig1 checks it against its shadow registers.
- Load-use: while the instruction in ID reads the rd of a load in EX, fetch holds and EX
  gets a bubble; the next cycle the load data comes from MEM/WB.
- Loads and stores: Mig1Lsu writes stores and sends load reads in EX: nothing after EX
  can fault, so an instruction that leaves EX always completes. The word arrives in
  MEM/WB, where Mig1LoadData takes the loaded value.
- Halt: EBREAK decides in EX: fetch stops, ID is flushed; `halt=1` comes the cycle after
  it retired in MEM/WB; resume redirects fetch to `halt_pc + 4`.

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
| `insn`, `trap` | the instruction; 1 when it faulted (it writes nothing, fetch continues at mtvec) |
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
`make config` generates `mig1_config_pkg.sv` (struct `mig1_cfg_t` and its default
`MIG1_CFG`; Mig1Cpu, Mig1Core and Mig1Fetch take it as parameter `CFG`), the linker
script `sw/riscv/mig1.ld` and `sw/riscv/mig1_config.h`; test `design_mig1.config` fails
when they are out of date.

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
| `design_mig1.config` | generated files are up to date with `cfg/mig1_config.yaml` |
| `design_mig1.sv2v` | Mig1Core converts with sv2v and elaborates: sv2v decides which SystemVerilog Mig1 can use |

Not run from rv32ui: fence_i (writes code into memory, Mig1 fetches from a separate
instruction memory) and ma_data (misaligned loads and stores, Mig1 traps on them).
Not run from rv32mi: breakpoint (needs the trigger CSRs of Sdtrig) and pmpaddr (needs
PMP); both are optional extensions Mig1 does not have.

All run on the main simulator of the build (cmake option DARK_CIRCUIT_MAIN_SIMULATOR, by
default Verilator when it is installed); Mig1 is tested with Verilator, only Verilator is
guaranteed to work. TbMig1 is built once; its plusargs (`+expect_regs`, `+resumes`,
`+riscv_test`, ...) are explained at the top of `tb_mig1.sv`. Run: `make run R=mig1`,
`make run L=riscv-tests`; `V=1` shows the paths of trace files.

## CPI

Cycles of every program at each step of the pipeline, measured with TbMig1 (Verilator):
instructions retired and cycles from reset to the halt (or the store to `tohost` of
riscv-tests, environment startup included). CPI is cycles per instruction. The code taken
over from Mig2 on 2026-10-23 has the cycles of the last column.

- 2-stage: IF | EX, before the 5-stage work, 2026-10-18.
- 3-stage (5a): IF | ID | EX with interlock, 2026-10-18. Redirects cost 2 bubbles
  instead of 1, an instruction that uses the rd of the one before it waits 1 cycle.
- 4-stage (5b): IF | ID | EX | MEM/WB, 2026-10-19. Loads lose their extra cycle; using
  the rd of the instruction before costs 2, of the one 2 before 1.
- 4-stage with forwarding: 2026-10-19. Results forwarded to ID, load-use 1 bubble.

With forwarding the 4-stage core still needs more cycles than the 2-stage one: a taken
branch costs 2 bubbles instead of 1, and the pipeline takes longer to fill. A deeper
pipeline can only win with a faster clock, see Area and speed.

| Programs | Count | Instructions | 2-stage cycles | CPI | 3-stage cycles | CPI | 4-stage cycles | CPI | 4-stage + fwd cycles | CPI |
|---|---|---|---|---|---|---|---|---|---|---|
| own programs (`test/design/mig1/*.S`, semihosting) | 17 | 421 | 655 | 1.56 | 822 | 1.95 | 926 | 2.20 | 724 | 1.72 |
| riscv-tests rv32ui | 40 | 14722 | 16111 | 1.09 | 21758 | 1.48 | 26246 | 1.78 | 16806 | 1.14 |
| riscv-tests rv32um | 8 | 2549 | 3885 | 1.52 | 4778 | 1.87 | 5563 | 2.18 | 4049 | 1.59 |
| riscv-tests rv32mi | 14 | 2112 | 2373 | 1.12 | 3305 | 1.56 | 3976 | 1.88 | 2645 | 1.25 |

<details><summary>Every program</summary>

| Program | Instructions | 2-stage cycles | CPI | 3-stage cycles | CPI | 4-stage cycles | CPI | 4-stage + fwd cycles | CPI |
|---|---|---|---|---|---|---|---|---|---|
| `alu_prog` | 28 | 29 | 1.04 | 32 | 1.14 | 35 | 1.25 | 31 | 1.11 |
| `branch` | 58 | 78 | 1.34 | 111 | 1.91 | 130 | 2.24 | 99 | 1.71 |
| `csr` | 39 | 40 | 1.03 | 52 | 1.33 | 64 | 1.64 | 42 | 1.08 |
| `fetch` | 5 | 6 | 1.20 | 9 | 1.80 | 12 | 2.40 | 8 | 1.60 |
| `illegal_csr_readonly` | 13 | 16 | 1.23 | 23 | 1.77 | 28 | 2.15 | 18 | 1.38 |
| `illegal_csr_unknown` | 13 | 16 | 1.23 | 23 | 1.77 | 28 | 2.15 | 18 | 1.38 |
| `illegal_ecall` | 11 | 13 | 1.18 | 18 | 1.64 | 22 | 2.00 | 16 | 1.45 |
| `illegal_ones` | 13 | 16 | 1.23 | 23 | 1.77 | 28 | 2.15 | 18 | 1.38 |
| `illegal_zero` | 13 | 16 | 1.23 | 23 | 1.77 | 28 | 2.15 | 18 | 1.38 |
| `load_store` | 43 | 64 | 1.49 | 71 | 1.65 | 59 | 1.37 | 48 | 1.12 |
| `misaligned_jalr` | 13 | 15 | 1.15 | 22 | 1.69 | 28 | 2.15 | 18 | 1.38 |
| `misaligned_lw` | 13 | 15 | 1.15 | 22 | 1.69 | 28 | 2.15 | 18 | 1.38 |
| `misaligned_sh` | 13 | 15 | 1.15 | 22 | 1.69 | 28 | 2.15 | 18 | 1.38 |
| `muldiv` | 21 | 156 | 7.43 | 164 | 7.81 | 170 | 8.10 | 160 | 7.62 |
| `resume` | 6 | 13 | 2.17 | 16 | 2.67 | 19 | 3.17 | 19 | 3.17 |
| `rv32mi_csr` | 168 | 180 | 1.07 | 251 | 1.49 | 310 | 1.85 | 194 | 1.15 |
| `rv32mi_illegal` | 120 | 137 | 1.14 | 194 | 1.62 | 234 | 1.95 | 156 | 1.30 |
| `rv32mi_instret_overflow` | 108 | 120 | 1.11 | 162 | 1.50 | 192 | 1.78 | 134 | 1.24 |
| `rv32mi_lh-misaligned` | 117 | 132 | 1.13 | 182 | 1.56 | 217 | 1.85 | 147 | 1.26 |
| `rv32mi_lw-misaligned` | 175 | 196 | 1.12 | 280 | 1.60 | 343 | 1.96 | 217 | 1.24 |
| `rv32mi_ma_addr` | 316 | 372 | 1.18 | 524 | 1.66 | 620 | 1.96 | 421 | 1.33 |
| `rv32mi_ma_fetch` | 237 | 267 | 1.13 | 385 | 1.62 | 473 | 2.00 | 299 | 1.26 |
| `rv32mi_mcsr` | 101 | 112 | 1.11 | 151 | 1.50 | 179 | 1.77 | 125 | 1.24 |
| `rv32mi_sbreak` | 109 | 123 | 1.13 | 170 | 1.56 | 203 | 1.86 | 139 | 1.28 |
| `rv32mi_scall` | 98 | 109 | 1.11 | 152 | 1.55 | 184 | 1.88 | 122 | 1.24 |
| `rv32mi_sh-misaligned` | 125 | 141 | 1.13 | 194 | 1.55 | 231 | 1.85 | 157 | 1.26 |
| `rv32mi_shamt` | 109 | 122 | 1.12 | 168 | 1.54 | 201 | 1.84 | 137 | 1.26 |
| `rv32mi_sw-misaligned` | 179 | 201 | 1.12 | 280 | 1.56 | 337 | 1.88 | 223 | 1.25 |
| `rv32mi_zicntr` | 150 | 161 | 1.07 | 212 | 1.41 | 252 | 1.68 | 174 | 1.16 |
| `rv32ui_add` | 506 | 532 | 1.05 | 700 | 1.38 | 852 | 1.68 | 560 | 1.11 |
| `rv32ui_addi` | 283 | 300 | 1.06 | 411 | 1.45 | 509 | 1.80 | 319 | 1.13 |
| `rv32ui_and` | 526 | 552 | 1.05 | 784 | 1.49 | 1000 | 1.90 | 580 | 1.10 |
| `rv32ui_andi` | 239 | 256 | 1.07 | 356 | 1.49 | 443 | 1.85 | 275 | 1.15 |
| `rv32ui_auipc` | 99 | 112 | 1.13 | 153 | 1.55 | 181 | 1.83 | 127 | 1.28 |
| `rv32ui_beq` | 332 | 369 | 1.11 | 473 | 1.42 | 548 | 1.65 | 408 | 1.23 |
| `rv32ui_bge` | 350 | 396 | 1.13 | 513 | 1.47 | 592 | 1.69 | 444 | 1.27 |
| `rv32ui_bgeu` | 375 | 421 | 1.12 | 563 | 1.50 | 667 | 1.78 | 469 | 1.25 |
| `rv32ui_blt` | 332 | 369 | 1.11 | 474 | 1.43 | 550 | 1.66 | 408 | 1.23 |
| `rv32ui_bltu` | 357 | 394 | 1.10 | 524 | 1.47 | 625 | 1.75 | 433 | 1.21 |
| `rv32ui_bne` | 332 | 371 | 1.12 | 478 | 1.44 | 554 | 1.67 | 412 | 1.24 |
| `rv32ui_jal` | 96 | 109 | 1.14 | 148 | 1.54 | 174 | 1.81 | 124 | 1.29 |
| `rv32ui_jalr` | 156 | 179 | 1.15 | 251 | 1.61 | 302 | 1.94 | 204 | 1.31 |
| `rv32ui_lb` | 270 | 311 | 1.15 | 410 | 1.52 | 472 | 1.75 | 308 | 1.14 |
| `rv32ui_lbu` | 270 | 311 | 1.15 | 410 | 1.52 | 472 | 1.75 | 308 | 1.14 |
| `rv32ui_ld_st` | 1005 | 1209 | 1.20 | 1681 | 1.67 | 1949 | 1.94 | 1173 | 1.17 |
| `rv32ui_lh` | 286 | 327 | 1.14 | 442 | 1.55 | 520 | 1.82 | 324 | 1.13 |
| `rv32ui_lhu` | 295 | 336 | 1.14 | 460 | 1.56 | 547 | 1.85 | 333 | 1.13 |
| `rv32ui_lui` | 106 | 117 | 1.10 | 158 | 1.49 | 188 | 1.77 | 130 | 1.23 |
| `rv32ui_lw` | 300 | 341 | 1.14 | 470 | 1.57 | 562 | 1.87 | 338 | 1.13 |
| `rv32ui_or` | 529 | 555 | 1.05 | 790 | 1.49 | 1009 | 1.91 | 583 | 1.10 |
| `rv32ui_ori` | 246 | 263 | 1.07 | 370 | 1.50 | 464 | 1.89 | 282 | 1.15 |
| `rv32ui_sb` | 459 | 524 | 1.14 | 663 | 1.44 | 745 | 1.62 | 523 | 1.14 |
| `rv32ui_sh` | 512 | 577 | 1.13 | 769 | 1.50 | 904 | 1.77 | 576 | 1.12 |
| `rv32ui_simple` | 82 | 92 | 1.12 | 124 | 1.51 | 146 | 1.78 | 104 | 1.27 |
| `rv32ui_sll` | 534 | 560 | 1.05 | 740 | 1.39 | 904 | 1.69 | 588 | 1.10 |
| `rv32ui_slli` | 282 | 299 | 1.06 | 409 | 1.45 | 506 | 1.79 | 318 | 1.13 |
| `rv32ui_slt` | 500 | 526 | 1.05 | 688 | 1.38 | 834 | 1.67 | 554 | 1.11 |
| `rv32ui_slti` | 278 | 295 | 1.06 | 401 | 1.44 | 494 | 1.78 | 314 | 1.13 |
| `rv32ui_sltiu` | 278 | 295 | 1.06 | 401 | 1.44 | 494 | 1.78 | 314 | 1.13 |
| `rv32ui_sltu` | 500 | 526 | 1.05 | 688 | 1.38 | 834 | 1.67 | 554 | 1.11 |
| `rv32ui_sra` | 553 | 579 | 1.05 | 774 | 1.40 | 953 | 1.72 | 607 | 1.10 |
| `rv32ui_srai` | 297 | 314 | 1.06 | 439 | 1.48 | 551 | 1.86 | 333 | 1.12 |
| `rv32ui_srl` | 547 | 573 | 1.05 | 762 | 1.39 | 935 | 1.71 | 601 | 1.10 |
| `rv32ui_srli` | 291 | 308 | 1.06 | 427 | 1.47 | 533 | 1.83 | 327 | 1.12 |
| `rv32ui_st_ld` | 525 | 585 | 1.11 | 817 | 1.56 | 989 | 1.88 | 549 | 1.05 |
| `rv32ui_sub` | 498 | 524 | 1.05 | 688 | 1.38 | 836 | 1.68 | 552 | 1.11 |
| `rv32ui_sw` | 520 | 585 | 1.12 | 787 | 1.51 | 932 | 1.79 | 584 | 1.12 |
| `rv32ui_xor` | 528 | 554 | 1.05 | 788 | 1.49 | 1006 | 1.91 | 582 | 1.10 |
| `rv32ui_xori` | 248 | 265 | 1.07 | 374 | 1.51 | 470 | 1.90 | 284 | 1.15 |
| `rv32um_div` | 137 | 445 | 3.25 | 496 | 3.62 | 536 | 3.91 | 458 | 3.34 |
| `rv32um_divu` | 138 | 446 | 3.23 | 498 | 3.61 | 539 | 3.91 | 459 | 3.33 |
| `rv32um_mul` | 500 | 526 | 1.05 | 692 | 1.38 | 842 | 1.68 | 554 | 1.11 |
| `rv32um_mulh` | 500 | 526 | 1.05 | 700 | 1.40 | 858 | 1.72 | 554 | 1.11 |
| `rv32um_mulhsu` | 500 | 526 | 1.05 | 700 | 1.40 | 858 | 1.72 | 554 | 1.11 |
| `rv32um_mulhu` | 500 | 526 | 1.05 | 700 | 1.40 | 858 | 1.72 | 554 | 1.11 |
| `rv32um_rem` | 137 | 445 | 3.25 | 496 | 3.62 | 536 | 3.91 | 458 | 3.34 |
| `rv32um_remu` | 137 | 445 | 3.25 | 496 | 3.62 | 536 | 3.91 | 458 | 3.34 |
| `semihosting` | 76 | 99 | 1.30 | 123 | 1.62 | 135 | 1.78 | 121 | 1.59 |
| `trap` | 43 | 48 | 1.12 | 68 | 1.58 | 84 | 1.95 | 54 | 1.26 |

</details>

## Synthesis

`make mig1_synth` converts Mig1Core with sv2v and synthesizes it with Yosys to generic
gates (not a test, about 20 s). It uses the struct versions of the library, not the fast
simulation models; Mig1Cpu is not synthesized (its memories are simulation models).
Outputs in `test/design/mig1/design_mig1.synth/` of the build directory: netlist.v,
stat.txt (cells of every module), yosys.log, synth.ys and tech.ys (the scripts that ran).
It fails on a latch or a structural problem (multiple drivers, undriven inputs, loops).
`make mig1_synth TECH=sky130` maps to sky130 cells and prints area and longest path
(report.txt in `test/design/mig1/design_mig1.synth_sky130/`; about 15 s).

## Area and speed (sky130)

Mig1Core mapped to the SkyWater sky130 standard cells (sky130_fd_sc_hd, typical corner
tt_025C_1v80) with Yosys 0.66 and ABC. Reproduce with `make mig1_synth TECH=sky130`.

| Mig1Core | |
|---|---|
| Area | 157 415 µm² (0.157 mm²), 18 461 cells |
| Longest logic path (ABC estimate) | 5.4 ns, about 186 MHz |

The longest path is the forwarding loop: ID/EX register, an EX part (funct3 decoded in
EX, then the multiplier or the ALU), EX result mux, forwarding mux into ID. Several paths
of this loop are within a few tenths of a nanosecond of it.

How the clock got there, 2026-10-21, measured on Mig2 before Mig1 took over its code
(each row adds one change to the row above):

| Change | Area (µm²) | Longest path (ns) |
|---|---|---|
| Struct library of 2026-10-20: carry-save array multiplier, ripple-carry adders | 146 248 | 24.1 |
| Int32Mul: WallaceMultiplier (Wallace tree and KoggeStoneAdder) | 149 656 | 14.4 |
| Alu1: KoggeStoneAdder | 153 223 | 10.9 |
| Divider: KoggeStoneAdder | 157 690 | 7.4 |
| Int32Mul: sign correction as three rows of one WallaceTree, one final adder | 157 004 | 5.6 |
| Decode delivers the M controls, MulDiv no longer decodes funct3 | 157 415 | 5.4 |

The delay is an estimate: ABC timing (stime) after buffering and gate sizing, without
wires (no wire load), without clock-to-Q and setup of the flip-flops; the ports of
Mig1Core count like flip-flops. Real timing (OpenSTA after placement) will differ; use
these numbers to compare designs and changes, not as a guaranteed fmax.

How: the liberty file from OpenROAD-flow-scripts commit bf3f9b3
(flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib); input the sv2v output of
Mig1Core with the struct library (the files of `make mig1_synth`); Yosys: read_liberty
-lib, hierarchy -check, synth -flatten -noabc, dfflibmap -liberty, abc -liberty with
script `strash; &get -n; &nf; &put; buffer; upsize; dnsize; topo; stime -p`, stat
-liberty. ABC maps the logic as written. No restructuring (fraig, scorr, dc2, dch, nor
synth's own ABC): it optimizes area and turns fast carry logic into chains, a 64-bit
Kogge-Stone adder takes 7.8 ns with it and 1.4 ns without. Until 2026-10-21 the flow
restructured; its numbers (the next section) can not be compared with these.

## Area and speed (sky130): 2-stage vs 4-stage

These numbers come from the flow before 2026-10-21 (ABC restructured the logic) and the
library of that day (carry-save array multiplier, ripple-carry adders): they compare the
two pipelines with each other, not with the current numbers above.

Mig1 mapped to the SkyWater sky130 standard cells (sky130_fd_sc_hd, typical corner) with
Yosys 0.66 and ABC, 2026-10-20, by hand, with the flow of that day. 2-stage: Mig1 of
commit 6fcd97d, the last 2-stage version. 4-stage with
forwarding: measured as Mig2Core, an unchanged copy of it. "Black box": Int32Mul is left
out (a black box), to time everything else.

| Design | Area (µm²) | Longest path (ns) | Clock (MHz) |
|---|---|---|---|
| 2-stage | 129 901 | 18.7 | 53 |
| 4-stage with forwarding | 141 063 | 16.9 | 59 |
| 2-stage, multiplier black box | 84 340 | 11.3 | 89 |
| 4-stage with forwarding, multiplier black box | 97 004 | 6.8 | 146 |

Critical paths (start and end point from ABC): 4-stage: ID/EX register, multiplier,
forwarding mux, ID/EX register; without the multiplier: divider result, result mux.
2-stage without the multiplier: instruction from imem, decode, register read, ALU and
branch, write back, all in one cycle.

Run time of all 79 programs, cycles (CPI table) x clock period:

| | 2-stage | 4-stage with forwarding | 4-stage faster by |
|---|---|---|---|
| with the multiplier | 23 024 x 18.7 ns = 431 µs | 24 224 x 16.9 ns = 410 µs | 5 % |
| multiplier black box | 23 024 x 11.3 ns = 260 µs | 24 224 x 6.8 ns = 166 µs | 1.6 x |

- The single-cycle multiplier sets the clock of both: with it, the 4-stage clock is
  11 % faster (operands come from the ID/EX register, not through decode and
  register read), which pays for its 5 % more cycles and little more.
- The deeper pipeline pays off only with a faster multiplier: without it, the 4-stage
  clock is 1.65 x faster. A black box is the limit; a real faster multiplier (pipelined,
  faster final adder) lands between the two rows.
- The 2-stage numbers are optimistic: its path starts at the imem output, counted like a
  flip-flop; a real memory adds its read time.
- The 4-stage core is 9 % larger: pipeline registers and forwarding.
- All delays are ABC estimates (no wires, no clock-to-Q and setup); good for comparing
  designs, not a guaranteed fmax.

## Known limits

- Reset does not block a store of the instruction in EX or the register write of the
  one in MEM/WB in that cycle.
- A load of memory outside the program image reads 0 on Verilator (2-state); a 4-state
  simulator gives X.

## Next

Bigger changes go to Mig2 first: pipeline bubbles visible in the trace, a faster
multiplier, Spike cosim (lockstep), a Zbb slice, a single memory instead of two. Mig1
stays the simple core and takes changes that keep it simple. The commit point stays in
EX, because nothing faults after it on Mig1; a later commit point (WB, store buffer)
comes with caches.
