# Mig1: RV32I RISC-V CPU

Mig1 is a small RISC-V CPU: RV32I base integer instructions, no CSRs, no interrupts.
It passes riscv-tests rv32ui (40 of 42 tests; fence_i and ma_data do not apply, see Testing).

- 2-stage pipeline: IF (fetch) | EX (everything else).
- Harvard: instruction memory and data memory, both with 1 clock read latency
  (like SRAM and FPGA block RAM). Mig1Cpu loads the same program image into both.
- Stops (halt) on EBREAK; a debugger resumes it. Stops for good (illegal) on faults.
- Runs C programs with semihosting (print, exit code): the same binary code as on QEMU.
- Retire trace of every completed instruction (RVFI-lite), for testbenches.

RTL is in this directory, configuration in `cfg/`, tests in `test/design/mig1/`.

## Files

| File | What |
|------|------|
| `mig1_pkg.sv` | Mig1Pkg: widths, port and boundary structs, kind_t, decoded_t |
| `mig1_config_pkg.sv` | Mig1ConfigPkg, generated from `cfg/mig1_config.yaml` |
| `mig1_fetch.sv`, `mig1_control.sv`, `mig1_decode.sv`, `mig1_regs.sv`, `mig1_alu.sv`, `mig1_branch.sv`, `mig1_lsu.sv` | the parts |
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
    rd value = ALU result | link | load data, chosen by ex_dec.rd_src;
               Mig1Regs writes it when ex_done=1
    ex_dec, branch, lsu -> Mig1Control -> if_ctrl (run, stall, redirect, target) -> Mig1Fetch
                                       -> ex_done, halt, illegal, halt_pc
```

Mig1Core only connects parts; its signals have the prefix of their stage (`if_`, `ex_`).
Each part works on "the instruction in its stage" and does not know which stage that
is, so the same parts fit a 5-stage pipeline.

| Part        | Stage | Does |
|-------------|-------|------|
| Mig1Fetch   | IF    | PC (PrgCounter), imem request; holds on stall, jumps on redirect and reset |
| Mig1Control | -     | run, stall, redirect, halt, faults, resume; ex_done: the instruction completes |
| Mig1Decode  | EX    | instruction -> decoded_t: kind, registers, funct3, alt, immediate, controls |
| Mig1Regs    | EX    | x0..x31, 2 reads + 1 write; the debug port owns read port 0 and the write port while halted |
| Mig1Alu     | EX    | rd value of OP, OP-IMM, LUI, AUIPC; address rs1 + imm of loads and stores |
| Mig1Branch  | EX    | taken, target, misaligned target; link = pc + 4 for JAL, JALR |
| Mig1Lsu     | EX    | dmem requests, store strobes, load data extension, misaligned address, load stall |

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

## Halt, faults and debug

| Instruction in EX | Completes (rd, memory, retire) | halt | illegal | resume |
|---|---|---|---|---|
| EBREAK | yes | 1 | 0 | continues at halt_pc + 4 |
| ECALL, illegal encoding | no | 1 | 1 | no effect, final |
| taken jump/branch to an address not divisible by 4 | no | 1 | 1 | no effect, final |
| load/store with misaligned address | no | 1 | 1 | no effect, final |

`halt_pc` is the address of the instruction that stopped the core; nothing is in flight
then. While halted, the debug port (`dbg_req_t`, `dbg_rsp_t`) reads a register
(combinational) and writes one per clock; `resume` for one clock restarts the core
after an EBREAK. ECALL is a fault because Mig1 has no traps.

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

`retire_t` has one entry per completed instruction: `valid`, `pc`, `insn`, and `rd`,
`rd_data` of the register write (both 0 when nothing is written, also for writes to x0,
as RVFI). Faulting and dropped instructions do not retire. TbMig1 checks the trace
and writes it to `<test>.<simulator>.trace`.

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
| `misaligned_{jalr,lw,sh}`, `illegal_{ecall,zero,ones}` | faults: halt at the instruction, nothing written |
| `rv32ui_*` (labels `riscv-tests`, `rv32ui`) | riscv-tests, environment `test/design/mig1/riscv_test.h` |

Not run from rv32ui: fence_i (writes code into memory, Mig1 fetches from a separate
instruction memory) and ma_data (misaligned loads and stores, Mig1 stops on them).

All run on Icarus (4-state: X in retire fails) and Verilator. TbMig1 is built once per
simulator; its plusargs (`+expect_regs`, `+resumes`, `+riscv_test`, ...) are explained
at the top of `tb_mig1.sv`. Run: `make run R=mig1`, `make run L=rv32ui`; `V=1` shows
the paths of trace files.

## Known limits

- Reset does not block a store or a register write of the instruction in EX in that cycle.
- A load of memory outside the program image is X on Icarus (test fails) and 0 on Verilator.
- No memory accesses in the retire trace yet.

## Next

rv32ui exit through semihosting (then the same binaries run on QEMU), Zicsr + Zicntr,
5-stage pipeline, M extension; full RVFI, then Spike cosim (lockstep) and riscv-formal.
