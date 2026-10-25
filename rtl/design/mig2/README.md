# Mig2: RISC-V CPU

Mig2 is where bigger changes of the Mig CPUs go first. It started as a copy of Mig1
(`rtl/design/mig1`) on 2026-10-19; Mig1 took over its code on 2026-10-23 and again on
2026-10-24, so today the two are the same design. See Mig1's README for how it works: its
pipeline, bubbles, pipeline view, tests, logs (here `DARK_CIRCUIT_MIG2_TRACE` and
`DARK_CIRCUIT_MIG2_KANATA`), synthesis (`make mig2_synth` here) and its area and speed;
this file describes what Mig2 changes from Mig1: nothing yet.

Simulation: Mig2 tests run on the main simulator of the build (cmake option
DARK_CIRCUIT_MAIN_SIMULATOR, by default Verilator when it is installed). Mig2 is tested
with Verilator; only Verilator is guaranteed to work.

Planned: branch prediction in ID, first a static guess (backward taken, forward not
taken), then the GShare predictor of `rtl/lib/block/gshare_branch_predictor`, a return
stack for returns and a BTB to predict in IF; a faster multiplier, Spike cosim
(lockstep), a Zbb slice, a single memory instead of two.
