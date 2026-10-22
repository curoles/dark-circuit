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
(report.txt in test/design/mig2/design_mig2.synth_sky130/; about 15 s).

## Area and speed (sky130)

Mig2Core mapped to the SkyWater sky130 standard cells (sky130_fd_sc_hd, typical corner
tt_025C_1v80) with Yosys 0.66 and ABC, 2026-10-21. Reproduce with
`make mig2_synth TECH=sky130`.

| Mig2Core | |
|---|---|
| Area | 157 415 µm² (0.157 mm²), 18 461 cells |
| Longest logic path (ABC estimate) | 5.4 ns, about 186 MHz |

The longest path is the forwarding loop: ID/EX register, an EX part (funct3 decoded in
EX, then the multiplier or the ALU), EX result mux, forwarding mux into ID. Several paths
of this loop are within a few tenths of a nanosecond of it.

How the clock got there, 2026-10-21 (each row adds one change to the row above):

| Change | Area (µm²) | Longest path (ns) |
|---|---|---|
| Struct library as copied from Mig1: carry-save array multiplier, ripple-carry adders | 146 248 | 24.1 |
| Int32Mul: WallaceMultiplier (Wallace tree and KoggeStoneAdder) | 149 656 | 14.4 |
| Alu1: KoggeStoneAdder | 153 223 | 10.9 |
| Divider: KoggeStoneAdder | 157 690 | 7.4 |
| Int32Mul: sign correction as three rows of one WallaceTree, one final adder | 157 004 | 5.6 |
| Mig2Decode delivers the M controls, Mig2MulDiv no longer decodes funct3 | 157 415 | 5.4 |

The delay is an estimate: ABC timing (stime) after buffering and gate sizing, without
wires (no wire load), without clock-to-Q and setup of the flip-flops; the ports of
Mig2Core count like flip-flops. Real timing (OpenSTA after placement) will differ; use
these numbers to compare designs and changes, not as a guaranteed fmax.

How: the liberty file from OpenROAD-flow-scripts commit bf3f9b3
(flow/platforms/sky130hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib); input the sv2v output of
Mig2Core with the struct library (the files of `make mig2_synth`); Yosys: read_liberty
-lib, hierarchy -check, synth -flatten -noabc, dfflibmap -liberty, abc -liberty with
script `strash; &get -n; &nf; &put; buffer; upsize; dnsize; topo; stime -p`, stat
-liberty. ABC maps the logic as written. No restructuring (fraig, scorr, dc2, dch, nor
synth's own ABC): it optimizes area and turns fast carry logic into chains, a 64-bit
Kogge-Stone adder takes 7.8 ns with it and 1.4 ns without. Until 2026-10-21 the flow
restructured; its numbers (16.9 ns and 141 063 µm² for Mig2Core, the Mig1 README) can
not be compared with these.
