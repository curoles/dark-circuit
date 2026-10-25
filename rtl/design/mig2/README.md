# Mig2: RISC-V CPU

Mig2 is where bigger changes of the Mig CPUs go first. It started as a copy of Mig1
(`rtl/design/mig1`) on 2026-10-19; Mig1 took over its code on 2026-10-23 and again on
2026-10-24, so today the two are the same design. See Mig1's README for how it works: its
pipeline, bubbles, pipeline view, tests, logs (here `DARK_CIRCUIT_MIG2_TRACE` and
`DARK_CIRCUIT_MIG2_KANATA`), synthesis (`make mig2_synth` here) and its area and speed;
this file describes what Mig2 changes from Mig1: a benchmark test.

Simulation: Mig2 tests run on the main simulator of the build (cmake option
DARK_CIRCUIT_MAIN_SIMULATOR, by default Verilator when it is installed). Mig2 is tested
with Verilator; only Verilator is guaranteed to work.

Planned: branch prediction in ID, first a static guess (backward taken, forward not
taken), then the GShare predictor of `rtl/lib/block/gshare_branch_predictor`, a return
stack for returns and a BTB to predict in IF; a faster multiplier, Spike cosim
(lockstep), a Zbb slice, a single memory instead of two.

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
