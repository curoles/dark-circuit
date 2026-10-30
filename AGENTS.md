# Notes for AI agents and contributors

Read README.md first: library layout, flists, make targets, tools.
This file has the rules that are not in README.md.

## Code style

- Indent 4 spaces, no tabs, Unix line endings (LF) and a newline at the end of every
  file, in all files (SV, C, assembly, CMake, Python).
- Line length: up to 100 characters; a longer line only when breaking it would read
  worse, and never over 120.
- Modules CamelCase (`DffAsyncRst`), files snake_case (`dff_async_rst.sv`),
  instances `u_` and name (`u_aoi22`, `u_mux4_0`). Cells use TSMC names and pins.
- Types end in `_t`, enum types in `_e` (`kind_e`, `alu_a_e`); an enum declares its
  storage, `enum logic [N-1:0]`, and its values are ALL_CAPS with a common prefix
  (`KIND_LOAD`, `RD_ALU`).
- Multiplexer inputs are zero-based: `sel` = k selects `in<k>`.
- Port connections: `.name` when the signal has the port's name, `.port(signal)`
  otherwise; mixing is fine: `u_x(.clk, .rst_n, .ctrl(if_ctrl))`. `.name` never
  creates an implicit net, a missing signal is an error. No `.*`: it hides what is
  connected. Old code is converted when it is touched anyway.
- Port groups: a module with many ports lists them in groups, one comment line per
  group (`// From ID`, `// From EX`, `// Debug`, `// To fetch and pipeline`); the
  module that instantiates it declares the wires in the same groups and connects them
  in the same order.
- Declarations: internal signals are `logic` or a package type (`word_t`); outputs
  are `output logic` when a process drives them, `output wire` when an `assign` does,
  or a package type; inputs are `input wire` or a package type. `wire` otherwise only
  for nets between instances in struct versions and for real multi-driver nets
  (inout). No `reg`. Why: a variable allows one driver, so a signal driven twice is an
  error in Verilator and Icarus, while a wire accepts it silently (Verilator picks one
  driver, Icarus shows x). Never declare with a value, `logic y = a & b;`: that is an
  initializer, computed once at time 0; declare, then `assign`. Old code is converted
  when it is touched anyway. When the load condition of a register is its own signal,
  it is named `<reg>_en` (`if (pc_en) pc_q <= pc_d;`); a condition that already has a
  meaning of its own is used directly (`if (ex_stop) halt_pc <= ex_fetch.pc;`).
- Reset: ports are `rst_n`, synchronous and active low, and code writes `!rst_n`. Only a
  module that uses the reset in two or more places may declare
  `logic rst;  // reset active` with `assign rst = !rst_n;`, because `rst || x` reads
  better than `!rst_n || x`; it then writes `rst` everywhere in that module, also
  `if (rst)` in its always_ff blocks: one spelling per module.
- Raw and qualified: when a signal is first computed without the condition that makes
  it count (valid, a fault, a flush) and then qualified, the first one is
  `<name>_raw` and the qualified one gets the plain name; then every use shows whether
  the condition is already in it.
- Long expressions: a statement that combines more than about three conditions, or that
  needs a comment to be read, is split into named signals, each saying what holds, with
  the reason in a comment above the group:
  1. a sub-expression used in several places becomes one signal;
  2. a signal that chooses between two cases (a mode, valid) splits the expression
     (Shannon decomposition): write the expression with that signal 1 and with it 0,
     each as a signal, and combine them with a ternary, `out = mode ? out_1 : out_0`;
  3. related conditions are grouped by meaning, a few per signal, as a balanced tree,
     not a long chain (synthesis maps the structure as written);
  4. the result is a sum of products, `(a && b) || (c && d)`, simplified (De Morgan) so
     that `!` stands on single signals, not on groups, and parentheses do not nest.
  A name must say more than its expression: no copies (`x = y`), no name per operator.
  Symmetric terms may stay in one statement:
  `(uses_rs1 && rs1 == ex_rd) || (uses_rs2 && rs2 == ex_rd)`.
  Example: `assign id_load_use = ex_load && id_reads_ex_rd;` (Mig2Control).
- A struct built from several values is written as one named assignment pattern,
  `assign id_ex_d = '{valid: …, pc: …, …};`, one field per line, without `default:`: the
  compiler checks that every field is set. A long value gets a name of its own first.
  A copy of a struct with a few changed fields is the whole copy followed by the changes,
  in `always_comb`: `retire = mem_ret; retire.valid = ex_mem_q.valid; ...` (Mig2Core).
- Numbers: in comparisons a plain number is fine (`count == 0`, `sel == 2`); in
  assignments and fills use `'0`/`'1` or a sized literal (`1'b0`, `4'd3`), never a
  plain number, because there a width mismatch changes the value silently.
  A multi-bit signal is never used as a boolean: `if (count != 0)`, not `if (count)`.
  Literals over 8 bits use `_` separators: `32'h8000_0000`.
- Operators: logical `!`, `&&`, `||` for true/false, bitwise `~`, `&`, `|`, `^` for
  data. A ternary nested in the true branch gets parentheses: `a ? (b ? x : y) : z`.
- Generate loops: new code writes `for (genvar i = 0; i < W; i++) begin : g_<name>`,
  without `generate`/`endgenerate`; every generate block is named `g_<name>`, so
  hierarchy paths read well (`u_reg_file.g_reg[3]`). Existing loops in the older,
  more explicit style (separate `genvar i;`, `i = i + 1`, `generate`) stay as they are.
- Processes: RTL (designs, behave and struct versions in the library) uses `always_ff`
  for flip-flops and `always_comb` for logic: the keyword says what the block is meant
  to be. Plain `always` only where code models time or checks rather than describing
  hardware: rtl/lib/sim, testbenches, the assertion macro. The dff gates keep their
  `always @(posedge clk)`: they model cells.
  `<=` only in `always_ff`, `=` only in `always_comb`, never both in one block. In
  `always_comb` every variable gets a value on every path (defaults first, or `else`
  and `default`): a missing path is a latch (Verilator LATCH). No `X` is assigned.
- State machines: a state enum `<name>_state_e`; one `always_comb` computes
  `<name>_state_d` and the outputs, with defaults first (next state = current state)
  and a comment above each state's case item; one `always_ff` holds only the reset and
  `<name>_state_q <= <name>_state_d`.
- Case: plain `case`/`casez`, no `unique` or `priority` (they are synthesis promises:
  if one is ever false, hardware differs from simulation); state exclusivity with
  `DC_ASSERT`, e.g. `$onehot0`. Every case has a `default`, except a case that lists all
  values of an enum: without `default`, Verilator (CASEINCOMPLETE) reports every case
  that misses a value added to the enum later.
- Packages: a module imports in its header the packages it uses throughout
  (`module X import Mig2Pkg::*; (`). A name used in only a few places, or whose origin
  matters to the reader (a spec constant next to design constants), is written with
  its package: `RiscvPkg::CAUSE_BREAKPOINT`. A package of many short names that only
  the body needs (an encoding table) is imported in the body: Mig2Decode imports
  RiscvInstrPkg there. Inside a package, names from other packages are always
  qualified (an import in a package is not passed on to its importers).
- No hierarchical references (`u_core.u_alu.result`) in RTL: only testbenches use them.
- File header: every file starts with a block comment, then its `include lines, then
  the module or package:
  ```
  /* <Title>: <one-sentence summary>.
   *
   * <What it does, its timing, the rules a user of the module must know.>
   *
   * @author    Igor Lesik
   * @copyright 2026 Igor Lesik, MIT License
   */
  ```
  The first sentence is the summary (Doxygen takes it as the brief). A port, parameter,
  struct field or internal signal gets a trailing `//` comment on its line, unless its
  name, or a comment above its group, already says what it is (`clk`, the inputs `a` and
  `b` of an And2, `imm_i`).
  No other Doxygen markup (`/**`, `@brief`, `///<`): a documentation filter turns these
  conventions into Doxygen comments. Generated files start with their "generated"
  line instead. Files without @author and @copyright get them when touched anyway.
  A long module (more than about 150 lines) starts each part of its body (faults,
  halt and resume, interlock, outputs, assertions) with a comment line naming it.
  A module instantiated in one or two places says where in a paragraph of its own
  (`Mig2Core instantiates it in EX, for the instruction in EX.`); a module used in many
  places (library blocks, gates) does not.
- Every SystemVerilog function is `automatic`; its arguments and result have types,
  it returns with `return x;`, and it reads only its arguments, parameters and
  constants, never module signals.
- Macros: a global macro carries the project prefix (`DC_ASSERT`,
  `DARK_CIRCUIT_USE_SVA`); a macro used only inside one file is named `_NAME` and
  `` `undef``'d after its last use.
- Stage prefixes: in modules that combine pipeline stages (a design's core, control,
  pipeline registers), every signal that belongs to one stage starts with its stage:
  if_, id_, ex_, mem_, wb_ (mem_ also for a merged MEM/WB stage). Signals of no single
  stage keep plain names: interfaces (imem_req, retire), state of the whole core
  (running, halt_pc), control between stages (pipe_ctrl, redirect). Parts that work
  on "the instruction in their stage" (Alu, Lsu, ...) use no prefixes: they do not know
  their stage. Then adding a stage is a mechanical split along the prefixes.
- Compute once, carry forward: in a pipeline, what a later stage needs about an item
  (an instruction, a request, a packet) is computed in the earliest stage that can
  compute it and travels with the item as ready fields of its stage struct (for
  example decoded_t, grouped by the part that uses them). A later stage reads those
  fields; it does not work them out again from raw data (the instruction, its kind,
  an address). This holds at every stage: decode produces controls, and a later
  stage passes on what it has computed for the stages after it (EX gives MEM/WB the
  load size and offset, not the instruction). Valid and flush gate only state changes
  (a register load, a start, a stall, a write), never data selects: the data of a
  bubble does not matter, and keeping valid out of the datapath keeps stall and flush
  logic off its timing path.
- Type parameters: when writing or refactoring, look for modules that store or move
  a value without computing on it (pipeline registers, FIFOs, memories, flip-flops,
  multiplexers). `parameter type T` makes the type part of the interface
  (`Mig2PipeReg #(.T(id_ex_t))`) instead of a width. Not for blocks that compute on
  bits (adders, shifters). In the library: a typed wrapper <Block>T next to <Block>.
- Struct versions of blocks use blocks, parts and gates only, never cells and never
  behavioral operators; behave versions are plain SV.
- Lint: Verilator runs with `-Wall` and warnings are errors. Disable a warning only
  locally with `/* verilator lint_off X */ ... lint_on`, and a comment why.
- Comments must not start with the word "verilator": Verilator reads them as pragmas.
- No WaveDrom in comments.

## Simulator traps (measured)

Icarus means Icarus 13, the version the project uses.

- Icarus and packages: a package must come before its first use in the file list;
  dc_parse_test_args() puts the flists before the testbench.
- Icarus and type parameters: they work (`parameter type T`, `#(.T(item_t))`),
  except `.T(...)` in an instance inside a module whose own type parameter is also
  named T: a syntax error (to the parser T is a type there). Name the outer type
  parameter differently (FifoVldRdyT uses TT).
- Icarus does not parse named assignment patterns `'{field: value}`.
- Icarus does not allow a field of a struct parameter in a constant expression,
  `localparam W = CFG.mem_addr_width;` ("A hierarchical reference ... is not allowed
  in a constant expression").
- Icarus does not support `inside`; use `case` or `==`.
- Icarus crashes (assert in elab_expr.cc) on an indexed part-select of a struct field,
  `s.f[i -: w]`; copy the field to a plain vector and select on that.
- Icarus has no queues of packed structs ("Queue of type netstruct_t is not yet
  supported"); queue plain vectors of `$bits(T)` and assign to and from T.
- Icarus says "sorry: constant selects in always_* processes are not fully supported"
  for `s.field` or `v[3:0]` inside `always_comb`; results are right (the process is
  sensitive to all bits). A function or an `assign` into a signal avoids the message.
- Icarus does not find a name imported from a package inside an instance port
  expression, `.left_right(funct3 == F3_SLL)`, nor a name alone, `.in2(BM_CTZ)`: it
  silently makes an implicit wire. For code that must run on Icarus, compute the value with
  `assign` into a signal and connect the signal, or write the name with its package,
  `.in2(ComputeCoreBitmanipPkg::BM_CTZ)`.
- Icarus evaluates a `?:` on a genvar written directly in an instance port connection,
  `.wr_data((w == 0) ? a : b)`, as X (Verilator gets it right). Assign a vector and connect
  its element, `assign v = {b, a};` and `.wr_data(v[w])`, or a wire per generate branch.
- Undeclared names: no `default_nettype in the code. Verilator -Wall rejects them
  (IMPLICIT; in an expression always an error), and every design is built with it.
  sv2v declares an undeclared name of a port connection as a wire, and Yosys makes
  undeclared names wires unless read_verilog -noautowire, which the synthesis script
  uses.
- A variable with an initializer in a static function is initialized once at time 0;
  Icarus silently returns wrong values, Verilator refuses. Hence `automatic` everywhere.
- Only `$fatal` makes `vvp` exit with an error; `$error` does not fail a test.
- Icarus elaboration tasks (`$fatal` in a generate block) take one plain string: no
  format arguments (`"WAYS=%0d", WAYS` does not compile), and the finish number must be
  given (`$fatal(1, "...")`).
- Icarus cannot read a function's own name as a variable inside the function
  (`stamp[f]` in function f): it compiles, then vvp stops with "unresolved functor
  reference". Use a local variable and `return` it.

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
- A feature with variants is one enum field of the config struct, not several bools:
  `mul_e mul;` with `MUL_SINGLE_CYCLE`, `MUL_PIPELINED`, `MUL_ITERATIVE` (and `MUL_NONE`
  if the feature can be left out); the design picks the implementation with
  `if (CFG.mul == MUL_PIPELINED) begin : g_mul_pipelined`. One field can not express an
  impossible combination, which two bools (`has_mul`, `mul_fast`) can.
- It composes: a design's struct contains sub-structs per subsystem, for example a
  later mig3_cfg_t with `cache_cfg_t l1i, l1d;` and a `bus_cfg_t`. A library block
  takes only its own sub-struct (`Cache #(.CFG(CFG.l1d))`), never the design's.
- A variant (another configuration in a test) is a whole struct: a localparam that
  copies the default with changed fields, or a second YAML.

## Assertions

Assertions are the rules of a design written as code next to the logic they guard: they
document intent and stop the simulation in the cycle a rule breaks.

- `include "dark_circuit_assert.svh" (rtl/lib/macro; every build passes the include path)
  gives:
  - `DC_ASSERT(a_name, expr)`: expr holds at every rising clk out of reset;
    Verilator and Icarus.
  - `DC_ASSERT_NEXT(a_name, cause, effect)`: cause at a clock edge implies effect at
    the next one; concurrent SVA, only with DARK_CIRCUIT_USE_SVA (Verilator builds).
  - `DC_STATIC_ASSERT(a_name, cond)`: a check of parameters at elaboration (cond is a
    constant expression): a false cond stops the build on Verilator and Icarus and stops
    synthesis. At module level, no clk needed. Use it for parameter legality (a power of
    2, a minimum size) instead of `initial if (...) $fatal`, which fires only when a
    simulation starts and which synthesis ignores.
  Both need clk and rst_n in scope; no semicolon after them; a failure is $fatal;
  synthesis never sees them (sv2v removes them).
- What to assert:
  1. A comment that states a rule ("at most one source applies", "nothing is in flight
     while halted"): put the assertion under it, and the comment becomes executable.
  2. Contracts at ports: what a module assumes about its inputs (every block that
     receives a valid/ready channel asserts rule 2 on it).
  3. Facts that span modules or cycles (EX is empty while halted; a stalled instruction
     stays in EX): they catch bugs no single module's code shows.
- What not to assert: a restatement of the line above it (it can not fail), or behavior
  the module defines as legal (Fifo ignores a write when full).
- Name `a_<what holds>`, so the failure message reads as the broken rule.
- Every new assertion gets a mutation check that breaks exactly the rule it states and
  sees this assertion fire, not only a later test failure (a mutation that only breaks
  nearby logic may never violate the rule). An assertion catches only what the tests
  drive; it does not replace a test.

## Testbenches

- Pure SystemVerilog, stop at the first mismatch with `$fatal(1, ...)`, always give
  the top module (`-s`, `--top-module`).
- X and Z checks inside `` `ifndef VERILATOR ``: Verilator is 2-state.
- Small or fast tests run on Icarus and Verilator; slow suites on the main simulator.
- A test that is slow on event-driven Icarus (big struct versions) checks many cases
  under `` `ifdef VERILATOR `` and a few otherwise, so that it runs in about 1-2 s on
  Icarus; exhaustive small widths on both.
- Block tests run the same testbench with `block_behave.flist` and `block_struct.flist`.

## Adding things

- Block: `rtl/lib/block/<b>/{behave,struct}/` with `<b>.flist` each, a `-F` line in
  `block_behave.flist` and `block_struct.flist`, a test in `test/block/<b>/`,
  the block name in the README layout.
- Order for a block: the behave version first, with its test (the test is the spec both
  versions must meet), then the struct version against the same test. Writing the struct
  version is a review of the design: look for simplifications (a cheaper state, a shared
  block such as PriorityEncoder, events that exclude each other and need no priority) and
  take one that helps back into the behave version and the test, so that both versions
  stay one design and the struct version does not drift into a different one. Examples:
  BitMatrixLru's victim became the highest invalid way, so that both versions use
  PriorityEncoder; CreditBarrier keeps what is still missing instead of a sum.
- Design: every design has `rtl/design/<d>/README.md`: what it is, parts, timing,
  limits, tests. Update it in the same change as the design.
- Design configuration: edit `rtl/design/<d>/cfg/<d>_config.yaml` or a template,
  run `make config`, commit the YAML and the generated files.
- RISC-V encodings and CSR addresses: `tools/riscv_opcodes.sh` regenerates
  `rtl/lib/riscv/riscv_instr_pkg.sv` and `riscv_csr_pkg.sv`.
- Generated files start with "THIS FILE IS GENERATED, DO NOT EDIT MANUALLY!":
  change their source instead, they are committed.

## Knowledge base

`kb/` keeps why the code is as it is: decisions with the options rejected, invariants,
measurements, attempts that were dropped (`kb/README.md`); its paths mirror the repository.

- Before changing code with an `@kb:` tag, read its record.
- Never delete or move code with an `@kb:` tag, or the tag itself, without deciding what
  happens to its record: update the record and its anchors; move it with the code (its path
  mirrors the code); or, when the decision itself is undone, turn the record into a
  `dropped` record that says why. Never delete a record silently: the knowledge is lost.
- Keep the knowledge base in mind while working. When a change decides something the code
  does not explain (a choice between options, an invariant other code relies on, a
  measurement, an attempt that is dropped), write the record and put `@kb: <id>` at the
  code, in the same change, and show it with the code.
- Run `make kb` after adding records, or moving, renaming or deleting tagged code.

## Repository

- `old2020/` is the old code, kept for reference; port from it, do not edit it.
- Run `make test` before committing; `make help` lists the targets.
