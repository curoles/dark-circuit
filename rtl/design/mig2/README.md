# Mig2: RISC-V CPU

Mig2 is where bigger changes of the Mig CPUs go first. It started as a copy of Mig1
(`rtl/design/mig1`) on 2026-10-19; on 2026-10-23 Mig1 took over its code, so today the
two are the same design: RV32IM, Zicsr, Zicntr, machine-mode traps, 4-stage pipeline
IF | ID | EX | MEM/WB with forwarding. See Mig1's README for how it works, its tests,
synthesis (`make mig2_synth` here) and its area and speed; this file describes what Mig2
changes from Mig1: nothing yet.

Simulation: Mig2 tests run on the main simulator of the build (cmake option
DARK_CIRCUIT_MAIN_SIMULATOR, by default Verilator when it is installed). Mig2 is tested
with Verilator; only Verilator is guaranteed to work.

Planned: pipeline bubbles visible in the trace, a faster multiplier, Spike cosim
(lockstep), a Zbb slice, a single memory instead of two.
