# Notes for AI agents and contributors

Read README.md first: library layout, flists, make targets, tools.
This file has the rules that are not in README.md.

## Code style

- Indent 4 spaces, no tabs, in all files (SV, C, assembly, CMake, Python).
- Modules CamelCase (`DffAsyncRst`), files snake_case (`dff_async_rst.sv`),
  instances `u_` and name (`u_aoi22`, `u_mux4_0`). Cells use TSMC names and pins.
- Multiplexer inputs are zero-based: `sel` = k selects `in<k>`.
- Port connections: `.name` when the signal has the port's name, `.port(signal)`
  otherwise; mixing is fine: `u_x(.clk, .rst_n, .ctrl(if_ctrl))`. `.name` never
  creates an implicit net, a missing signal is an error. No `.*`: it hides what is
  connected. Old code is converted when it is touched anyway.
- Every SystemVerilog function is `automatic`.
- Stage prefixes: in modules that combine pipeline stages (a design's core, control,
  pipeline registers), every signal that belongs to one stage starts with its stage:
  if_, id_, ex_, mem_, wb_ (mem_ also for a merged MEM/WB stage). Signals of no single
  stage keep plain names: interfaces (imem_req, retire), state of the whole core
  (running, halt_pc), control between stages (pipe_ctrl, redirect). Parts that work
  on "the instruction in their stage" (Alu, Lsu, ...) use no prefixes: they do not know
  their stage. Then adding a stage is a mechanical split along the prefixes.
- Type parameters: when writing or refactoring, look for modules that store or move
  a value without computing on it (pipeline registers, FIFOs, memories, flip-flops,
  multiplexers). `parameter type T` makes the type part of the interface
  (`Mig2PipeReg #(.T(id_ex_t))`) instead of a width. Not for blocks that compute on
  bits (adders, shifters). In the library: a typed wrapper <Block>T next to <Block>
  in the same file, inside `ifdef DARK_CIRCUIT_ENABLE_MODULE_TYPE_PARAM`, which the
  build defines for Verilator and sv2v; designs that need Icarus use the width version.
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
- Icarus 11 and type parameters: `parameter type T` is a syntax error, also in a
  module that is not instantiated (Icarus parses every file it gets). Library
  modules with type parameters are inside `ifdef DARK_CIRCUIT_ENABLE_MODULE_TYPE_PARAM`,
  not defined for Icarus.
- Undeclared names: no `default_nettype in the code. Verilator -Wall rejects them
  (IMPLICIT; in an expression always an error), and every design is built with it.
  sv2v declares an undeclared name of a port connection as a wire, and Yosys makes
  undeclared names wires unless read_verilog -noautowire, which the synthesis script
  uses.
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

## Valid/ready channels

This is the project's handshake convention: use it for every new interface where one
side may have to wait for the other, and reach for it by default when designing new
blocks and designs.

When to use it:
- Between blocks with variable latency or back-pressure: memories, caches, buses, the
  NoC, queues, anything that can be busy.
- Not needed for combinational blocks (an adder, a decoder) or for stages inside one
  design that one control stalls and flushes together (a CPU pipeline, Mig2PipeReg).
- Existing fixed-latency interfaces (the Mig1 and Mig2 memory ports) stay as they are
  until a design needs them to wait, for example when caches come; then they change
  to channels.

A channel moves items in one direction: valid and the data go from sender to receiver,
ready goes back from receiver to sender (Chisel Decoupled, AXI-Stream). Rules:

1. Transfer: one item moves on a rising edge where valid and ready are both 1.
2. No take-backs: once valid is 1, the sender keeps valid and the data unchanged
   until the transfer.
3. No loops: valid must not depend combinationally on ready; ready may depend on valid.
4. Reset: valid is 0 during and right after reset; the data means nothing while valid
   is 0, so it needs no reset.

Ports: a library block has three ports per channel, `<ch>_valid`, `<ch>_ready`,
`<ch>_data` (data of a type parameter T, see Code style). A design keeps one struct per
direction for its port groups (`<group>_req_t`, `<group>_rsp_t`) and connects their
fields to the channels of the blocks.

Build with the library blocks instead of new handshake logic: FifoVldRdyT (block/fifo),
SkidBufferT (block/skid_buffer: a register stage that cuts combinational paths in both
directions). A missing block (arbiter, credit counter, ...) is added to the library
with these rules. Test every channel under random stalls with SimVldRdySource and
SimVldRdySink (sim/sim_vld_rdy.sv): the sink checks rules 2 and 4, the testbench checks
that every item arrives once, in order, unchanged (see test/block/skid_buffer).

## Design configuration

Every design has one configuration struct, not loose module parameters: one
description per configuration. A large design has dozens of knobs (core options,
cache sizes and ways, bus widths, NoC topology); a struct carries them through the
hierarchy as one parameter, so a new knob does not change module headers and the
knobs can not disagree between modules.

- YAML stays the single source: `rtl/design/<d>/cfg/<d>_config.yaml`. `make config`
  generates the struct type `<d>_cfg_t` and its default `<D>_CFG` into
  `<d>_config_pkg.sv` (fields written by hand in the template `<d>_config_pkg.sv.j2`,
  values from the YAML), and from the same YAML the C header and the linker script.
  A new knob: a line in the YAML and a field in the template.
- Modules that read a knob, or pass the struct down to one, take
  `parameter <d>_cfg_t CFG = <D>_CFG`; other modules do not get it (no struct that
  every module depends on). Example: Mig2Cpu, Mig2Core, Mig2Fetch.
- The struct holds instance knobs (addresses, sizes, optional features, variants).
  ISA-wide widths and the types built from them (WIDTH, word_t, ...) stay constants
  in the design package: a package type can not depend on a module parameter.
- It composes: a design's struct contains sub-structs per subsystem, for example a
  later mig3_cfg_t with `cache_cfg_t l1i, l1d;` and a `bus_cfg_t`. A library block
  takes only its own sub-struct (`Cache #(.CFG(CFG.l1d))`), never the design's.
- A variant (another configuration in a test) is a whole struct: a localparam that
  copies the default with changed fields, or a second YAML.
- Mig1 keeps its loose parameters (it is done and runs on Icarus).

## Testbenches

- Pure SystemVerilog, stop at the first mismatch with `$fatal(1, ...)`, always give
  the top module (`-s`, `--top-module`).
- X and Z checks inside `` `ifndef VERILATOR ``: Verilator is 2-state.
- Small or fast tests run on Icarus and Verilator; slow suites on the main simulator.
- A test that is slow on event-driven Icarus (big struct versions) checks many cases
  under `` `ifdef VERILATOR `` and a few otherwise; exhaustive small widths on both.
- Block tests run the same testbench with `block_behave.flist` and `block_struct.flist`.

## Adding things

- Block: `rtl/lib/block/<b>/{behave,struct}/` with `<b>.flist` each, a `-F` line in
  `block_behave.flist` and `block_struct.flist`, a test in `test/block/<b>/`,
  the block name in the README layout.
- Design: every design has `rtl/design/<d>/README.md`: what it is, parts, timing,
  limits, tests. Update it in the same change as the design.
- Design configuration: edit `rtl/design/<d>/cfg/<d>_config.yaml` or a template,
  run `make config`, commit the YAML and the generated files.
- RISC-V encodings and CSR addresses: `tools/riscv_opcodes.sh` regenerates
  `rtl/lib/riscv/riscv_instr_pkg.sv` and `riscv_csr_pkg.sv`.
- Generated files start with "THIS FILE IS GENERATED, DO NOT EDIT MANUALLY!":
  change their source instead, they are committed.

## Repository

- `old2020/` is the old code, kept for reference; port from it, do not edit it.
- Run `make test` before committing; `make help` lists the targets.
