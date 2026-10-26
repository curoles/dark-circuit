# Mig2: RISC-V CPU

Mig2 is where bigger changes of the Mig CPUs go first. It started as a copy of Mig1
(`rtl/design/mig1`) on 2026-10-19; Mig1 took over its code on 2026-10-23 and again on
2026-10-24, so today the two are the same design. See Mig1's README for how it works: its
pipeline, bubbles, pipeline view, tests, logs (here `DARK_CIRCUIT_MIG2_TRACE` and
`DARK_CIRCUIT_MIG2_KANATA`), synthesis (`make mig2_synth` here) and its area and speed;
this file describes what Mig2 changes from Mig1: branch prediction in ID, a benchmark test,
cycle ceilings.

Simulation: Mig2 tests run on the main simulator of the build (cmake option
DARK_CIRCUIT_MAIN_SIMULATOR, by default Verilator when it is installed). Mig2 is tested
with Verilator; only Verilator is guaranteed to work.

Planned: the GShare predictor of `rtl/lib/block/gshare_branch_predictor` in place of the
static guess, with a second benchmark; a return stack for returns and a BTB to predict in
IF; a faster multiplier, Spike cosim (lockstep), a Zbb slice, a single memory instead of
two.

## Branch prediction

Mig2 guesses the direction of a conditional branch in ID (Mig2BranchPredict): static,
backward taken, forward not taken (BTFN), from the sign of the offset: a branch back mostly
closes a loop. For a branch guessed taken ID redirects fetch to pc + imm, as for a JAL (see
JAL from ID in Mig1's README): one bubble, `BUBBLE_PRED_TAKEN`. The guess goes with the
branch to EX (`id_ex_t.redirected`); EX redirects when the outcome differs from what ID
did: a taken branch guessed not taken goes to its target, a branch guessed taken but not
taken to the next instruction. A wrong guess costs two bubbles: `BUBBLE_COND_BRANCH`, a
guess corrected by EX (after a wrong taken guess, one of the two is the `pred_taken`
bubble of ID). `test/design/mig2/branch_id.S` runs the corners: every pair of guess and
outcome, a branch waiting in ID for load data or behind a division, on the wrong path,
back to back, to misaligned targets.

Cycles out of reset and not halted, CPI:

| Programs | without prediction | BTFN |
|---|---|---|
| Dhrystone (benchmark) | 1.379 | 1.298 |
| own programs | 1.744 | 1.733 |
| riscv-tests rv32ui | 1.140 | 1.165 |
| riscv-tests rv32um | 1.588 | 1.612 |
| riscv-tests rv32mi | 1.249 | 1.294 |

Dhrystone runs 5.8 % fewer cycles. Its taken branches cost 15.6 % of its cycles before,
two bubbles each; a guess in ID can at best halve that, because a correct taken guess still
costs the bubble of the redirect from ID (only a BTB in IF removes it). About 89 % of the
guesses are right. The riscv-tests get slower: their loops run twice, taken once and then
not, and BTFN guesses the second branch wrong. Area +150 µm² (159 076 µm²), the longest
path does not change (5.3 ns).

## Cycle ceilings

A worse prediction does not make a test fail, it only costs cycles. The tests that measure
prediction have a ceiling: `+max_cycles` of TbMig2 set to their cycles of today, branch_id
(always) and Dhrystone (benchmark). A change that makes them slower fails ("no end after N
cycles (+max_cycles)"); one that makes them faster passes, and its cycles become the new
ceiling. The ceiling counts the cycles of TbMig2 (its PASS line), halted cycles included.

## Benchmark

`design_mig2_dhrystone` runs Dhrystone of riscv-tests (`benchmarks/dhrystone`, unchanged,
with the support of `sw/riscv/bench`) for about 5 s: real code with branches and calls, to
measure cycles and bubbles; its own results are not printed. It is not part of regular
testing: the test exists only with the cmake option `DARK_CIRCUIT_BENCHMARKS`.

```
make cmake D=mig2 CMAKE_ARGS=-DDARK_CIRCUIT_BENCHMARKS=ON
make run D=mig2 L=benchmark
```

2026-10-24: 1 640 000 instructions in about 2 270 000 cycles, CPI about 1.38 (6 runs of
500 loops; bubbles: taken branches, returns, divisions, calls, load-use).
