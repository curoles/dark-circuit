# Mig2: RISC-V CPU

Mig2 is where bigger changes of the Mig CPUs go first. It started as a copy of Mig1
(`rtl/design/mig1`) on 2026-10-19; on 2026-10-23 Mig1 took over its code. Both are RV32IM,
Zicsr, Zicntr, machine-mode traps, 4-stage pipeline IF | ID | EX | MEM/WB with forwarding.
See Mig1's README for how it works, its tests, synthesis (`make mig2_synth` here) and its
area and speed; this file describes what Mig2 changes from Mig1: JAL redirects fetch from
ID, bubbles carry their reason, and a pipeline view for Konata.

Simulation: Mig2 tests run on the main simulator of the build (cmake option
DARK_CIRCUIT_MAIN_SIMULATOR, by default Verilator when it is installed). Mig2 is tested
with Verilator; only Verilator is guaranteed to work.

Planned: a faster multiplier, Spike cosim (lockstep), a Zbb slice, a single memory
instead of two.

## JAL from ID

JAL is always taken and its target, pc + imm, is known as soon as ID decodes it. ID
redirects fetch when the JAL leaves ID (Mig2Control), so only the instruction requested in
the same cycle is dropped: one bubble instead of two. The JAL goes on to EX and retires as
before; EX does not redirect again. ID does not redirect when an older instruction in EX
redirects or halts the core (the JAL is dropped with ID), while EX holds a division (the
JAL waits in ID and redirects when it leaves), or when the target is not divisible by 4
(EX traps: misaligned fetch); `test/design/mig2/jal_id.S` runs these cases. All program
tests: 114 JALs, 24 389 cycles before, 24 275 after. This is the redirect path that branch
prediction will use; JALR stays in EX (its rs1 can still be on its way from a load).

## Bubbles

A bubble is a pipeline slot without an instruction. Every pipeline register (IF/ID, ID/EX,
EX/MEM) carries, with valid=0, the reason of its bubble (`bubble_e` in Mig2Pkg), and the
retire port reports it (`retire.bubble`, not part of RVFI): every cycle out of reset and
not halted retires an instruction or a bubble, so the reasons add up to all cycles that
retire nothing.

| Reason | Bubbles | Made by |
|---|---|---|
| `BUBBLE_FILL` | 3 | the pipeline fills: after reset, after resume |
| `BUBBLE_COND_BRANCH` | 2 | taken conditional branch in EX |
| `BUBBLE_DIR_JUMP` | 1 | JAL in ID (calls too), see JAL from ID |
| `BUBBLE_INDIR_JUMP` | 2 | JALR in EX that is not a return (indirect calls too) |
| `BUBBLE_RET` | 2 | JALR return in EX: rs1 is x1 or x5, rd is not rs1 (RISC-V hint table) |
| `BUBBLE_TRAP` | 2 | trap in EX: fetch goes to mtvec |
| `BUBBLE_XRET` | 2 | MRET in EX: fetch goes to mepc |
| `BUBBLE_LOAD_USE` | 1 | the next instruction reads the rd of a load |
| `BUBBLE_DIV` | 33 | EX holds a division |

A redirect drops the instructions in ID and IF; both bubbles get the class of the
instruction in EX (Mig2Control), a slot that already was a bubble keeps its reason
(Mig2PipeReg). Decode marks returns (`br.ret`). The classes are those of branch
prediction: with a predictor, they count mispredictions.

The trace of TbMig2 (`+trace`, see Logs) has a line per bubble, in place, and the run
ends with the count per reason; branch.S:

```
      21 pc=00000048 insn=00308463
      22 bubble cond_branch
      23 bubble cond_branch
      24 pc=00000050 insn=00209463
...
99 cycles = 58 retired + 41 bubbles: fill 3 cond_branch 24 dir_jump 8 indir_jump 6
```

TbMig2 checks every bubble against the instructions around it: a redirect bubble follows
an instruction of its class, at most two; a load-use bubble sits between a load and an
instruction that reads its rd; division bubbles come right before a division; fill
bubbles only before the first instruction after reset or resume.

## Pipeline view (Konata)

Mig2Core reports its pipeline in `pipe_trace` (`pipe_trace_t` in Mig2Pkg): the slot of
every stage (valid, bubble reason, pc) and how the slots move at the rising edge
(redirect, stalls, flush). TbMig2 follows every instruction through the stages and checks
its view against the slots in every cycle of every program test. With `+kanata=<file>` it
writes the view as a log for [Konata](https://github.com/shioyadan/Konata), a pipeline
viewer: a row per instruction, its stages IF, ID, EX, MEM over the cycles, stalls as
longer stages, the instructions of the wrong path flushed; label: pc and instruction
word, tooltip: the bubbles before the instruction.

With `DARK_CIRCUIT_MIG2_KANATA` (see Logs) the tests write the log; open, for example,
`test/design/mig2/design_mig2_branch.verilator.kanata` of the build directory in Konata
(from Windows through `\\wsl.localhost\...`).

## Logs

Program tests write logs only on request, because every log is a file per test:

| CMake option | Plusarg of TbMig2 | Log, in `test/design/mig2/` of the build directory |
|---|---|---|
| `DARK_CIRCUIT_MIG2_TRACE` | `+trace=<file>` | `<test>.verilator.trace`: retired instructions, bubbles, debugger and semihosting actions, the count per bubble reason |
| `DARK_CIRCUIT_MIG2_KANATA` | `+kanata=<file>` | `<test>.verilator.kanata`: the pipeline view for Konata |

```
make cmake D=mig2 CMAKE_ARGS="-DDARK_CIRCUIT_MIG2_TRACE=ON -DDARK_CIRCUIT_MIG2_KANATA=ON"
make run D=mig2 R=design_mig2_branch V=1
```

The options stay in the CMake cache; `=OFF` turns a log off again. Without the trace, a
failing test shows its `$fatal` message; run it again with the trace to see what led there.
