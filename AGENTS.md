# Notes for AI agents and contributors

Read README.md first: library layout, flists, make targets, tools.
This file has the rules that are not in README.md.

## Code style

- Indent 4 spaces, no tabs, in all files (SV, C, assembly, CMake, Python).
- `test/third_party/` is copied by scripts in `tools/` and never edited by hand;
  the style rules of this file do not apply there.
- Modules CamelCase (`DffAsyncRst`), files snake_case (`dff_async_rst.sv`),
  instances `u_` and name (`u_aoi22`, `u_mux4_0`). Cells use TSMC names and pins.
- Multiplexer inputs are zero-based: `sel` = k selects `in<k>`.
- Port connections: `.name` when the signal has the port's name, `.port(signal)`
  otherwise; mixing is fine: `u_x(.clk, .rst_n, .ctrl(if_ctrl))`. `.name` never
  creates an implicit net, a missing signal is an error. No `.*`: it hides what is
  connected. Old code is converted when it is touched anyway.
- Every SystemVerilog function is `automatic`.
- Struct versions of blocks use blocks, parts and gates only, never cells and never
  behavioral operators; behave versions are plain SV.
- Lint: Verilator runs with `-Wall` and warnings are errors. Disable a warning only
  locally with `/* verilator lint_off X */ ... lint_on`, and a comment why.
- Comments must not start with the word "verilator": Verilator reads them as pragmas.
- No WaveDrom in comments.

## Simulator traps (measured)

- Icarus 11 and packages: import the package in the module header,
  `module X import Pkg::*; #(`. Package structs used only as `Pkg::type`, with no
  module importing the package, crash Icarus (assert in elab_type.cc).
- Icarus 11 and typedef'd vectors: a port of a vector typedef (`insn_t`) does not
  elaborate; write the range, `input logic [INSN_WIDTH-1:0] insn`. Structs are fine.
- Icarus 11: one declaration per line, `wire a = x, b = y;` is rejected.
- Icarus 11 does not support `inside`; use `case` or `==`.
- Icarus 11 does not support casts to an enum (`kind_t'(x)`) or to a width (`AW'(x)`);
  keep enum values as bits and compare them with the enum names, slice integers.
- Icarus 11 warns "constant selects in always_* processes are not currently supported"
  for `s.field` or `v[3:0]` inside `always_comb`; select with `assign` into a signal first.
- Icarus 11 does not find a name imported from a package inside an instance port
  expression, `.left_right(funct3 == F3_SLL)`: it silently makes an implicit wire.
  Compute the value with `assign` into a signal and connect the signal.
- A variable with an initializer in a static function is initialized once at time 0;
  Icarus silently returns wrong values, Verilator refuses. Hence `automatic` everywhere.
- Only `$fatal` makes `vvp` exit with an error; `$error` does not fail a test.

## Testbenches

- Pure SystemVerilog, stop at the first mismatch with `$fatal(1, ...)`, always give
  the top module (`-s`, `--top-module`).
- X and Z checks inside `` `ifndef VERILATOR ``: Verilator is 2-state.
- Small or fast tests run on Icarus and Verilator; slow suites on the main simulator.
- Block tests run the same testbench with `block_behave.flist` and `block_struct.flist`.

## Adding things

- Block: `rtl/lib/block/<b>/{behave,struct}/` with `<b>.flist` each, a `-F` line in
  `block_behave.flist` and `block_struct.flist`, a test in `test/block/<b>/`,
  the block name in the README layout.
- Design: every design has `rtl/design/<d>/README.md`: what it is, parts, timing,
  limits, tests. Update it in the same change as the design.
- Design configuration: edit `rtl/design/<d>/cfg/<d>_config.yaml` or a template,
  run `make config`, commit the YAML and the generated files.
- RISC-V encodings: `tools/riscv_opcodes.sh` regenerates `rtl/lib/riscv/riscv_instr_pkg.sv`.
- Generated files start with "THIS FILE IS GENERATED, DO NOT EDIT MANUALLY!":
  change their source instead, they are committed.

## Repository

- `old2020/` is the old code, kept for reference; port from it, do not edit it.
- Run `make test` before committing; `make help` lists the targets.
