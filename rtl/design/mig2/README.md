# Mig2: RISC-V CPU

Mig2 starts as a copy of Mig1 (`rtl/design/mig1`) on 2026-10-19: RV32IM, Zicsr, Zicntr,
machine-mode traps, 4-stage pipeline IF | ID | EX | MEM/WB with forwarding. See Mig1's
README for how it works; this file describes what Mig2 changes.

Simulation: Mig2 tests run on the main simulator of the build (cmake option
DARK_CIRCUIT_MAIN_SIMULATOR, by default Verilator when it is installed). Mig2 is tested
with Verilator; only Verilator is guaranteed to work.

Syntax: Mig2Core must convert with sv2v (test design_mig2.sv2v); sv2v decides which
SystemVerilog Mig2 can use.

Synthesis: make mig2_synth (sv2v, then Yosys, generic gates; not a test, about 20 s).
Outputs in test/design/mig2/design_mig2.synth/ of the build directory: netlist.v,
stat.txt (cells of every module), yosys.log, synth.ys (the script that ran). It fails
on a latch or a structural problem (multiple drivers, undriven inputs, loops).
