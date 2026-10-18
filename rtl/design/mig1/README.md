# Mig1: RV32I RISC-V CPU

Mig1 is a small RISC-V CPU: RV32IM (base integer instructions, multiply and divide),
Zicsr (CSR instructions) and Zicntr (counters), machine-mode traps; no interrupts yet.
It passes riscv-tests rv32ui (40 of 42 tests), rv32um (8 of 8) and rv32mi (14 of 16) with
their standard environment; the other tests need features Mig1 does not have, see Testing.

- 2-stage pipeline: IF (fetch) | EX (everything else).
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
| `mig1_core.sv` | Mig1Core: connects the parts, synthesizable, memories are outside |
| `mig1_cpu.sv` | Mig1Cpu: Mig1Core with SimROM (imem) and SimRAM (dmem), for simulation |
| `mig1.flist` | files in compile order |

## Parts and dataflow

```
IF  Mig1Fetch (PC) --imem_req--> imem
                                   | 1 clock
EX  imem_rsp -> ex_insn -> Mig1Decode -> ex_dec
    ex_dec -> Mig1Regs -> rs1 data, rs2 data
    rs1, rs2, imm, pc -> Mig1Alu    -> ALU result: rd value, or address of load/store
                      -> Mig1Branch -> branch (taken, target, misaligned), link = pc + 4
    address, rs2      -> Mig1Lsu    -> dmem_req; 1 clock later dmem_rsp -> load data
                                       lsu (stall, misaligned)
    ex_dec, rs1       -> Mig1Csr    -> old CSR value; CSR write when the instruction completes
    rs1, rs2          -> Mig1MulDiv -> product (1 cycle) or quotient/remainder (34 cycles,
                                       muldiv stall)
    rd value = ALU result | link | load data | CSR value | M result, chosen by ex_dec.rd_src;
               Mig1Regs writes it when ex_done=1
    ex_dec, branch, lsu, CSR fault, muldiv stall -> Mig1Control -> if_ctrl (run, stall, redirect, target) -> Mig1Fetch
                                       -> ex_done, ex_trap (to Mig1Csr), halt, halt_pc
```

Mig1Core only connects parts; its signals have the prefix of their stage (`if_`, `ex_`).
Each part works on "the instruction in its stage" and does not know which stage that
is, so the same parts fit a 5-stage pipeline.

| Part        | Stage | Does |
|-------------|-------|------|
| Mig1Fetch   | IF    | PC (PrgCounter), imem request; holds on stall, jumps on redirect and reset |
| Mig1Control | -     | run, stall, redirect, traps (cause, mtval), halt, resume; ex_done: the instruction completes |
| Mig1Decode  | EX    | instruction -> decoded_t: kind, registers, funct3, alt, immediate, controls |
| Mig1Regs    | EX    | x0..x31, 2 reads + 1 write; the debug port owns read port 0 and the write port while halted |
| Mig1Alu     | EX    | rd value of OP, OP-IMM, LUI, AUIPC; address rs1 + imm of loads and stores |
| Mig1Branch  | EX    | taken, target, misaligned target; link = pc + 4 for JAL, JALR |
| Mig1Lsu     | EX    | dmem requests, store strobes, load data extension, misaligned address, load stall |
| Mig1Csr     | EX    | CSRs, counters, trap CSRs; CSR instructions read the old value and write the new one |
| Mig1MulDiv  | EX    | M extension: Int32Mul (combinational), Int32Div (32 clocks, stalls), RISC-V results of divide by 0 and overflow |

Boundary structs are in Mig1Pkg, named by their producer: `fetch_t`, `fetch_ctrl_t`,
`decoded_t`, `branch_t`, `lsu_t`; memory and debug ports are `<group>_req_t`/`_rsp_t`.
Decode gives controls (`rd_we`, `rd_src`, `uses_rs1`, `uses_rs2`); units derive their
operation from `kind`, `funct3` and `alt` (RiscvPkg `F3_*` names the funct3 values).

## Pipeline timing

Every instruction takes one cycle in EX, plus:

| Case | Extra cycles | Why |
|------|--------------|-----|
| taken branch, JAL, JALR | 1 | the instruction fetched after it is dropped (one bubble) |
| load | 1 | data comes 1 clock after the read request; the load waits in EX |
| store | 0 | written in its cycle in EX |
| multiply | 0 | Int32Mul is combinational |
| divide, remainder | 33 | Int32Div takes 32 clocks; start, 32 steps, then the result |

Measured: branch.S retires 58 instructions in 78 cycles, load_store.S 43 in 64.

```
straight-line      taken branch B -> T          load L
cycle  1  2  3     cycle  1   2    3   4         cycle  1   2       3       4
IF     a  b  c     IF     B   B+4  T   T+4       IF     L   (hold)  L+4     L+8
EX        a  b     EX         B    -   T         EX         L 1st   L 2nd   L+4
                   (B+4 arrives with valid=0)    dmem       read    data
```

- Redirect: Mig1Branch decides in EX; Mig1Control redirects fetch to the target and the
  instruction requested in the same cycle comes back with `fetch.valid=0`.
- Stall: in the first cycle of a load, fetch holds everything (PC, imem output, fetch);
  the load and its registers stay, so its address is the same in the second cycle.

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
| `mie`, `mip` | read 0, writes ignored | no interrupts yet |
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

## Known limits

- Reset does not block a store or a register write of the instruction in EX in that cycle.
- A load of memory outside the program image is X on Icarus (test fails) and 0 on Verilator.

## Next

Structural versions of the M blocks, interrupts (timer), 5-stage pipeline; Spike cosim (lockstep) and riscv-formal
on the RVFI trace.
