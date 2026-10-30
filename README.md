# DARKCIRCUIT

## Library layout

```
rtl/lib/
  cell/          1-bit cells with TSMC-style names and pins: INV, ND2, MUX2, DFQ, ...
    generic/     behavioral
    cmos/        pmos/nmos transistors, bigger cells are made of smaller cells
    builtin/     Verilog primitives (not, nand, ...), optional UDP for flops and latch
    tsmc/        wrappers around TSMC library cells: INV -> INVD1, ND2 -> ND2D1, ...
  gate/          WIDTH-parameterized gates: Inv, Nand2, Mux2, Dff, ...
    generic/     behavioral
    cell/        built from cells, or from other gates of gate/cell
  part/          parts made of gates: CarrySaveAdder, RippleCarryAdder, GatedClk, LimDff
  block/         blocks: Counter, Decoder, MuxN, PriorityEncoder, ShiftReg, Sram1R1W,
                 RegFile, RegFileSram, BarrelShifter, PrgCounter, Fifo, SkidBuffer, Incr,
                 Alu1, AddCmp, Lfsr, StochasticBitstreamGen, CsaMultiplier, Divider, ...
    <block>/behave/  behavioral version, fast to simulate
    <block>/struct/  version made of blocks, parts and gates
    jtag_core_dbg/   JTAG TAP and core debug port copied from old2020;
                     not in aggregate flists, not tested yet
  numeric/       number formats, built on blocks: int32/mul Int32Mul, int32/div Int32Div;
                 <format>/<op>/<kind>/{behave,struct}, aggregate flists like block/
  riscv/         RISC-V instruction encodings and CSR addresses, generated from riscv-opcodes
                 by tools/riscv_opcodes.sh
  macro/         include files kept for old code; use $clog2, not `CLOG2
  sim/           simulation models for testbenches: SimClkGen, SimRstGen, SimRAM, SimROM,
                 SimLatencyRAM
rtl/design/mig1/ Mig1 RISC-V CPU (RV32IM, 4-stage pipeline), see its README.md
rtl/design/mig2/ Mig2 RISC-V CPU, where bigger changes of Mig1 go first
cmake/           cmake helpers, one file per simulator
test/gate/       testbenches of gates
test/part/<part>/   testbench of a part
test/block/<block>/ testbench of a block
test/numeric/<format>/<op>/ testbench of a numeric unit
test/sim/        testbenches of simulation models
test/design/mig1/ tests of Mig1
test/design/mig2/ tests of Mig2
sw/riscv/        RISC-V software for tests: crt0.S, linker scripts, semihosting/, bench/
                 (support of the riscv-tests benchmarks)
test/sw/         tests of software, run on QEMU
old2020/         old 2020 code, kept for reference
```

Every directory has its flist, for example `cell/cmos/cell_cmos.flist`
or `gate/cell/gate_cell.flist`. File names in a flist are relative to the flist directory
(as Verilator `-F` expects). Icarus resolves file names of its command file `-f`
from the current directory, so the cmake helpers read flists and pass full paths.
A flist line `-F <file>` includes another flist, also relative to the flist directory.

### Blocks

A block can have two versions with the same module name and ports:
`behave/` (behavioral, fast to simulate) and `struct/` (made of blocks, parts and gates).
Every version has its flist, for example `block/counter/struct/counter.flist`.
Aggregate flists include one version of every block:

- `block_behave.flist`: `behave/`, or `struct/` if the block has only that one
- `block_struct.flist`: `struct/`, or `behave/` if the block has only that one

To mix versions, make your own flist with `-F` lines of the chosen block versions.
The struct version also needs `part.flist` and gate flists.

### Cell, gate and flavor

A **cell** is 1-bit, its module name is the TSMC cell name without drive strength
(`ND2` for TSMC `ND2D1`) and its pins are TSMC pin names (`A1`, `A2`, `ZN`).

A **gate** has parameter `WIDTH`, its module name is CamelCase (`Nand2`)
and its ports are `in1`, `in2`, `out`, ...

Cell directories `generic`, `cmos`, `builtin` and `tsmc` are **flavors**:
every flavor has the same cells with the same pins, only implementation differs.
Use gates in a design, then choose implementation by flists:

- behavioral gates: `gate_generic.flist`
- gates made of cells: `gate_cell.flist` and one `cell_<flavor>.flist`

Always give simulator the top module (`iverilog -s`, `verilator --top-module`),
then modules that the design does not use are not elaborated.

### Defines

- `DARK_CIRCUIT_FAKE_TSMC`: flavor `tsmc` uses fake TSMC cells defined in the same files,
  to work without TSMC library.
- `DARK_CIRCUIT_BUILTIN_UDP`: flavor `builtin` makes DFQ, DFCNQ and LHQ with Verilog UDP
  instead of always_ff and always_latch.

### Naming

- cell module: TSMC name without drive strength, `AOI22`
- gate module: CamelCase, `Aoi22`, `CmpEq`, `DffAsyncRst`
- file: module name in lower case, snake_case, `aoi22.sv`, `cmp_eq.sv`, `dff_async_rst.sv`
- instance: `u_` and name, `u_aoi22`, `u_mux4_0`
- multiplexer inputs: zero-based, `sel` = k selects `in<k>`;
  `Mux4` has `in0`..`in3` and `sel[1:0]`

### Cells

- basic: INV, BUF, ND2, ND3, NR2, NR3, AN2, AN3, OR2, OR3
- XOR: XOR2, XNR2, XOR3
- complex: AOI21, AOI22, AOI31, OAI21, OAI22
- inverted input: IND2, IND3, IIND3
- multiplexer: MUX2, MUX2N, MUX3, MUX4
- arithmetic: HA1, FA1, MAJ3, BENC, BML
- sequential: DFQ, DFCNQ (asynchronous clear), LHQ (latch)

### Gates

- basic: Inv, Buf, Nand2, Nand3, Nor2, Nor3, And2, And3, Or2, Or3
- XOR: Xor2, Xnor2, Xor3
- complex: Aoi21, Aoi22, Aoi31, Oai21, Oai22, Ind2, Ind3, Iind3
- multiplexer: Mux2, Mux2i, Mux3, Mux4, Mux8, Mux1hot2, Mux1hot3
- arithmetic: HalfAdder, FullAdder, FullAdderMaj3, FullAdderAoi, Maj3, Benc, Bml
- reduction: AndReduce, OrReduce, NorReduce, Parity, CmpEq, CmpNe
- sequential: Dff, DffEn, DffAsyncRst, DffAsyncRstEn, DffSyncRst, DffSyncRstEn, Latch

### Tests

Testbenches in `test/gate/` check every gate and stop at the first mismatch:
`tb_gate.sv` applies all input combinations to combinational gates,
`tb_gate_seq.sv` clocks, resets and enables sequential gates.
Each testbench runs with `gate_generic.flist` and with `gate_cell.flist`
over every cell flavor, so every cell is covered through its gate.

Every test of gates runs with Icarus and Verilator, except cell flavor `cmos`:
it models transistors and only 4-state Icarus shows its short circuits (x) and
floating outputs (z). Verilator is 2-state, so `tb_gate_seq.sv` skips its x checks
with `` `ifndef VERILATOR ``.

A **part** uses gates only, never cells. Tests of parts use `gate_generic.flist`
and run on the main simulator only, see [Simulators](#simulators).

A **block** struct version uses blocks, parts and gates, never cells. Tests of blocks run
the same testbench with `block_behave.flist` and with `block_struct.flist`
on the main simulator, so both versions must behave the same.

## Requirements

- CMake 3.20 or newer
- Icarus Verilog (`iverilog`, `vvp`) to run simulation tests
- Verilator 5.0 or newer to run simulation tests with Verilator
- RISC-V GNU toolchain (optional) to build RISC-V programs for tests,
  on Ubuntu: `sudo apt install gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf`
- QEMU (optional) to run RISC-V programs on `qemu-system-riscv32`,
  on Ubuntu: `sudo apt install qemu-system-misc`
- Python 3 with `python3-yaml` and `python3-jinja2` (optional) for `make config`
  and the checks of design configurations

## Build and test

`Makefile` wraps `cmake` and `ctest`, it has 11 targets:

- `make help`: explain targets and variables, also plain `make`
- `make cmake`: configure build directory
- `make build`: configure if needed and build
- `make test`: configure if needed, build and run all tests
- `make test_gates`: configure if needed, build and run tests of gates
- `make test_parts`: configure if needed, build and run tests of parts
- `make test_blocks`: configure if needed, build and run tests of blocks
- `make run R=<regex> L=<regex>`: configure if needed, build and run tests
  with name matching `R` and/or label matching `L`, for example `make run R=fifo`
- `make list`: configure if needed and list tests, name and labels of every test
- `make config`: generate files from design configurations,
  see [Design configuration](#design-configuration)
- `make kb`: check the knowledge base `kb/`: why the code is as it is, decisions and
  attempts that were dropped, linked to the code (see `kb/README.md`)

Configure is needed the first time and when `CMAKE_ARGS` are given;
after that cmake re-runs itself when `CMakeLists.txt` or flists change.

Build directory is outside of the source tree. There is one build tree per purpose,
chosen with `D=<tree>`, each in its own directory `build/<tree>` next to the repository
directory (for repository `~/prj/dark-circuit/dark-circuit`: `~/prj/dark-circuit/build/<tree>`):

- `D=full` (default): the library and all designs, every test
- `D=lib`: the library and its tests (gates, parts, blocks, numeric, sim, software)
- `D=<design>`, for example `D=mig1`: that design and its tests, not the library tests

```sh
make test D=lib          # working on the library
make test D=mig1         # working on Mig1
make test                # everything, before a commit
```

The cmake variables behind it: `DARK_CIRCUIT_DESIGNS` (`ALL`, a list of designs in
`test/design`, or empty) and `DARK_CIRCUIT_LIB_TESTS` (`ON`, `OFF`).

Run all tests:

```sh
make test
```

Run from any directory:

```sh
make -C <path-to>/dark-circuit test
```

Use other build directory (D still chooses what is in it):

```sh
make test BUILD_DIR=/tmp/dc-build
```

Pass options to cmake:

```sh
make test CMAKE_ARGS="-D DARK_CIRCUIT_USE_ICARUS=ON"
```

## Simulators

Use of every simulator is controlled by a cmake variable:

- Icarus Verilog: `DARK_CIRCUIT_USE_ICARUS`, tests have suffix and label `.icarus`
- Verilator: `DARK_CIRCUIT_USE_VERILATOR`, tests have suffix and label `.verilator`

Values of these variables:

- `AUTO`: use it if found (default)
- `ON`: require it, cmake fails if not found
- `OFF`: do not use it

Verilator older than 5.0 is treated as not found (or as an error with `ON`).

A test is added with `dc_add_<simulator>_test()`, which builds the testbench and
runs it once. A testbench that runs many tests, like `TbMig1` with one RISC-V
program per test, is built once with `dc_add_<simulator>_build()`, and every test
runs that build with `dc_add_<simulator>_run()`, see `test/design/mig1/CMakeLists.txt`.

Tests that need only one simulator, like tests of parts, run on the **main simulator**,
cmake variable `DARK_CIRCUIT_MAIN_SIMULATOR` selects it:

- `AUTO`: first used of Verilator, Icarus (default)
- `verilator`: Verilator, cmake fails if it is not used
- `icarus`: Icarus Verilog, cmake fails if it is not used

```sh
make test_parts CMAKE_ARGS="-D DARK_CIRCUIT_MAIN_SIMULATOR=icarus"
```

## RISC-V programs

Tests that run RISC-V programs build them with the RISC-V GNU toolchain
into Verilog hex files for `SimRAM` and `SimROM` `load()`. Cmake variables:

- `DARK_CIRCUIT_USE_RISCV`: `AUTO`, `ON` or `OFF` like for simulators;
  without the toolchain these tests are disabled
- `DARK_CIRCUIT_RISCV_PREFIX`: prefix of the toolchain programs,
  default `riscv64-unknown-elf-`; other toolchains use for example
  `riscv32-unknown-elf-` or `riscv-none-elf-`
- `DARK_CIRCUIT_USE_QEMU`: `AUTO`, `ON` or `OFF`; with QEMU, programs also run on
  `qemu-system-riscv32` with semihosting as a reference, tests have suffix and label `.qemu`
- `DARK_CIRCUIT_USE_RISCV_TESTS`: `AUTO`, `ON` or `OFF`; riscv-tests are fetched when cmake
  configures a build directory the first time (about 10 MB, needs network; `AUTO` disables
  them when the repository can not be reached). Later configures and builds do not fetch.
  Without network: `-D FETCHCONTENT_SOURCE_DIR_RISCV_TESTS=<riscv-tests checkout>`

```sh
make test CMAKE_ARGS="-D DARK_CIRCUIT_RISCV_PREFIX=riscv-none-elf-"
```

Every program `<name>` gives `<name>.elf`, `<name>.hex`, `<name>.dis` (disassembly)
and `<name>.sym` (symbol table) in the build directory of its test.

## Mig1 tests

Tests of Mig1 programs (testbench `TbMig1`, `test/design/mig1/tb_mig1.sv`) write a
trace of retired instructions into `<test>.<simulator>.trace` in the build directory
of the test, for example `design_mig1_alu_prog.verilator.trace`:

```
      27 pc=00000068 insn=00000cb3 x25 <= 00000000
      28 pc=0000006c insn=00100073
```

The test prints the path of its trace file, `make run` shows it with `V=1`.
The file is complete also when the test fails. Plusargs of `TbMig1`
(`+trace`, `+expect_regs`, ...) are explained at the top of `tb_mig1.sv`.

Mig1 also runs the rv32ui (instructions) and rv32mi (machine mode: CSRs, traps) suites of
[riscv-tests](https://github.com/riscv-software-src/riscv-tests): self-checking tests
written by the RISC-V community, so the expected values do not come from this project.
Cmake fetches their source with the standard environment `env/p` at a pinned commit
into the build directory (`cmake/fetch.cmake`, BSD licenses there), and compiles the tests
with the rules of this project. A test ends with a store to the word `tohost`,
which TbMig1 finds in the symbol table of the program. Run them with `make run L=rv32ui`,
`make run L=rv32mi` or `make run L=riscv-tests`.

## Design configuration

A design has its configuration in `rtl/design/<design>/cfg/`: `<design>_config.yaml`
with values (memory size, reset address, ...) and Jinja2 templates of the files
that need them. `tools/config_gen.py` makes the files, they are committed:

- edit the YAML (or a template), run `make config`, commit the YAML and the changed files
- generated files start with `THIS FILE IS GENERATED, DO NOT EDIT MANUALLY!`
- test `<design>.config` (label `config`) fails when a generated file is out of date
- `DARK_CIRCUIT_USE_PYTHON`: `AUTO`, `ON` or `OFF`, like for simulators

## Running selected tests

After `make build`, call `ctest` directly, `<build-dir>` is the build directory:

```sh
ctest --test-dir <build-dir> -N                    # list tests
ctest --test-dir <build-dir> -R gate_cell_cmos     # tests with name matching regex
ctest --test-dir <build-dir> -L icarus             # tests with label icarus
ctest --test-dir <build-dir> --output-on-failure   # show output of failed tests
```

Every test has labels:

- its tool: `icarus`, `verilator`, `qemu` or `config`
- the first directory under `test/`: `gate`, `sim`, `part`, `block` or `sw`
- for tests deeper in `test/`, its own directory: `carry_save_adder`, `semihosting`, ...

`make list` shows name and labels of every test. `make run L=<regex>` and
`ctest -L <regex>` select tests by label; the label is a regex, `gate` also matches
`gated_clk`, use `'^gate$'` for the exact label.
