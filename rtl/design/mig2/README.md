# Mig2: RISC-V CPU

Mig2 is where bigger changes of the Mig CPUs go first. It started as a copy of Mig1
(`rtl/design/mig1`) on 2026-10-19; on 2026-10-23 Mig1 took over its code, so today the
two are the same design: RV32IM, Zicsr, Zicntr, machine-mode traps, 4-stage pipeline
IF | ID | EX | MEM/WB with forwarding. See Mig1's README for how it works, its tests,
synthesis (`make mig2_synth` here) and its area and speed; this file describes what Mig2
changes from Mig1: bubbles carry their reason, and a pipeline view for Konata.

Simulation: Mig2 tests run on the main simulator of the build (cmake option
DARK_CIRCUIT_MAIN_SIMULATOR, by default Verilator when it is installed). Mig2 is tested
with Verilator; only Verilator is guaranteed to work.

Planned: a faster multiplier, Spike cosim (lockstep), a Zbb slice, a single memory
instead of two.

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
| `BUBBLE_DIR_JUMP` | 2 | JAL in EX (calls too) |
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

The trace of TbMig2 (`+trace`) has a line per bubble, in place, and the run ends with the
count per reason; branch.S:

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

The log costs a file per test, so tests write it only on request:

```
make cmake D=mig2 CMAKE_ARGS=-DDARK_CIRCUIT_MIG2_KANATA=ON    # once, stays in the cache
make run D=mig2 R=design_mig2_branch V=1
```

then open `test/design/mig2/design_mig2_branch.verilator.kanata` of the build directory
in Konata (from Windows through `\\wsl.localhost\...`). `-DDARK_CIRCUIT_MIG2_KANATA=OFF`
turns it off again.
