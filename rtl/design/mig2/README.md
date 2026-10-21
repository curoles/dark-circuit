# Mig2: RISC-V CPU

Mig2 starts as a copy of Mig1 (`rtl/design/mig1`) on 2026-10-19: RV32IM, Zicsr, Zicntr,
machine-mode traps, 4-stage pipeline IF | ID | EX | MEM/WB with forwarding. See Mig1's
README for how it works; this file describes what Mig2 changes.

Simulation: Mig2 tests run on the main simulator of the build (cmake option
DARK_CIRCUIT_MAIN_SIMULATOR, by default Verilator when it is installed). Mig2 is tested
with Verilator; only Verilator is guaranteed to work.

Configuration: cfg/mig2_config.yaml (make config) gives struct mig2_cfg_t and its default
MIG2_CFG (Mig2ConfigPkg); Mig2Cpu, Mig2Core and Mig2Fetch take it as parameter CFG.

Syntax: Mig2Core must convert with sv2v (test design_mig2.sv2v); sv2v decides which
SystemVerilog Mig2 can use.

Synthesis: make mig2_synth (sv2v, then Yosys, generic gates; not a test, about 20 s).
Outputs in test/design/mig2/design_mig2.synth/ of the build directory: netlist.v,
stat.txt (cells of every module), yosys.log, synth.ys and tech.ys (the scripts that ran).
It fails on a latch or a structural problem (multiple drivers, undriven inputs, loops).
make mig2_synth TECH=sky130 maps to sky130 cells and prints area and longest path
(report.txt in test/design/mig2/design_mig2.synth_sky130/; about 50 s).

## Area and speed (sky130)

Mig2Core as copied from Mig1 (4-stage pipeline with forwarding), mapped to the SkyWater
sky130 standard cells (sky130_fd_sc_hd, typical corner tt_025C_1v80) with Yosys 0.66 and
ABC, 2026-10-20. Reproduce with `make mig2_synth TECH=sky130`.

| Mig2Core | |
|---|---|
| Area | 141 063 µm² (0.141 mm²), 16 526 cells |
| Longest logic path (ABC estimate) | 16.9 ns, about 59 MHz |

Blocks, each mapped alone with the same flow:

| Block | Area (µm²) | Longest path (ns) |
|---|---|---|
| Int32Mul | 43 039 | 16.25 |
| Mig2Csr | 15 210 | 4.80 |
| Mig2Alu | 5 693 | 5.04 |
| Mig2Branch | 3 387 | 4.36 |
| Mig2Forward | 1 934 | 1.08 |
| Mig2Lsu | 1 026 | 0.87 |
| Mig2Decode | 863 | 1.52 |

The single-cycle 32x32 multiplier (Int32Mul: carry-save array, ripple-carry final adder)
sets the clock: 16.3 of the 16.9 ns; the other blocks
are about 5 ns or less.

The delay is an estimate: ABC timing (stime) after buffering and gate sizing, without
wires (no wire load), without clock-to-Q and setup of the flip-flops; the ports of
Mig2Core count like flip-flops. Real timing (OpenSTA after placement) will differ; use
these numbers to compare designs and changes, not as a guaranteed fmax.

How: the liberty file from OpenROAD-flow-scripts commit bf3f9b3
(flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib); input the sv2v output of
Mig2Core with the struct library (the files of `make mig2_synth`); Yosys: read_liberty
-lib, hierarchy -check, synth -flatten, dfflibmap -liberty, abc -liberty with script
`strash; &get -n; &fraig -x; &put; scorr; dc2; dretime; strash; &get -n; &dch -f; &nf;
&put; buffer; upsize; dnsize; topo; stime -p`, stat -liberty.
