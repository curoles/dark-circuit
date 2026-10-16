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
  block/         blocks: Counter, Decoder, PriorityEncoder, ShiftReg, Sram1R1W, RegFile, RegFileSram, BarrelShifter, PrgCounter, Fifo, Incr, Alu1, AddCmp, ...
    <block>/behave/  behavioral version, fast to simulate
    <block>/struct/  version made of parts and gates
  macro/         include files kept for old code; use $clog2, not `CLOG2
  sim/           simulation models for testbenches: SimClkGen, SimRstGen, SimRAM, SimROM
cmake/           cmake helpers, one file per simulator
test/gate/       testbenches of gates
test/part/<part>/ testbench of a part
test/block/<block>/ testbench of a block
test/sim/        testbenches of simulation models
```

Every directory has its flist, for example `cell/cmos/cell_cmos.flist`
or `gate/cell/gate_cell.flist`. File names in a flist are relative to the flist directory
(as Verilator `-F` expects). Icarus resolves file names of its command file `-f`
from the current directory, so the cmake helpers read flists and pass full paths.
A flist line `-F <file>` includes another flist, also relative to the flist directory.

### Blocks

A block can have two versions with the same module name and ports:
`behave/` (behavioral, fast to simulate) and `struct/` (made of parts and gates).
Every version has its flist, for example `block/counter/struct/counter.flist`.
Aggregate flists include one version of every block:

| Flist               | Version of every block                                  |
|---------------------|---------------------------------------------------------|
| `block_behave.flist` | `behave/`, or `struct/` if the block has only that one |
| `block_struct.flist` | `struct/`, or `behave/` if the block has only that one |

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

| Implementation             | Flists                                       |
|----------------------------|----------------------------------------------|
| behavioral gates           | `gate_generic.flist`                         |
| gates made of cells        | `gate_cell.flist` and one `cell_<flavor>.flist` |

Always give simulator the top module (`iverilog -s`, `verilator --top-module`),
then modules that the design does not use are not elaborated.

### Defines

| Define                     | Effect                                                         |
|----------------------------|----------------------------------------------------------------|
| `DARK_CIRCUIT_FAKE_TSMC`   | flavor `tsmc` uses fake TSMC cells defined in the same files, to work without TSMC library |
| `DARK_CIRCUIT_BUILTIN_UDP` | flavor `builtin` makes DFQ, DFCNQ and LHQ with Verilog UDP instead of always_ff and always_latch |

### Naming

| What                | Rule                                   | Example                          |
|---------------------|----------------------------------------|----------------------------------|
| cell module         | TSMC name without drive strength       | `AOI22`                          |
| gate module         | CamelCase                              | `Aoi22`, `CmpEq`, `DffAsyncRst`  |
| file                | module name in lower case, snake_case  | `aoi22.sv`, `cmp_eq.sv`, `dff_async_rst.sv` |
| instance            | `u_` and name                          | `u_aoi22`, `u_mux4_0`            |
| multiplexer inputs  | zero-based, `sel` = k selects `in<k>`  | `Mux4`: `in0`..`in3`, `sel[1:0]` |

### Cells

| Group          | Cells                                     |
|----------------|-------------------------------------------|
| basic          | INV, BUF, ND2, ND3, NR2, NR3, AN2, AN3, OR2, OR3 |
| XOR            | XOR2, XNR2, XOR3                          |
| complex        | AOI21, AOI22, AOI31, OAI21, OAI22         |
| inverted input | IND2, IND3, IIND3                         |
| multiplexer    | MUX2, MUX2N, MUX3, MUX4                   |
| arithmetic     | HA1, FA1, MAJ3, BENC, BML                 |
| sequential     | DFQ, DFCNQ (asynchronous clear), LHQ (latch) |

### Gates

| Group          | Gates                                     |
|----------------|-------------------------------------------|
| basic          | Inv, Buf, Nand2, Nand3, Nor2, Nor3, And2, And3, Or2, Or3 |
| XOR            | Xor2, Xnor2, Xor3                         |
| complex        | Aoi21, Aoi22, Aoi31, Oai21, Oai22, Ind2, Ind3, Iind3 |
| multiplexer    | Mux2, Mux2i, Mux3, Mux4, Mux8, Mux1hot2, Mux1hot3 |
| arithmetic     | HalfAdder, FullAdder, FullAdderMaj3, FullAdderAoi, Maj3, Benc, Bml |
| reduction      | AndReduce, OrReduce, NorReduce, Parity, CmpEq, CmpNe |
| sequential     | Dff, DffAsyncRst, DffAsyncRstEn, DffSyncRst, DffSyncRstEn, Latch |

### Tests

Testbenches in `test/gate/` check every gate and stop at the first mismatch:
`tb_gate.sv` applies all input combinations to combinational gates,
`tb_gate_seq.sv` clocks, resets and enables sequential gates.
Each testbench runs with `gate_generic.flist` and with `gate_cell.flist` over every cell flavor,
so every cell is covered through its gate.

Every test of gates runs with Icarus and Verilator, except cell flavor `cmos`:
it models transistors and only 4-state Icarus shows its short circuits (x) and
floating outputs (z). Verilator is 2-state, so `tb_gate_seq.sv` skips its x checks
with `` `ifndef VERILATOR ``.

A **part** uses gates only, never cells. Tests of parts use `gate_generic.flist`
and run on the main simulator only, see [Simulators](#simulators).

A **block** struct version uses parts and gates, never cells. Tests of blocks run
the same testbench with `block_behave.flist` and with `block_struct.flist`
on the main simulator, so both versions must behave the same.

## Requirements

- CMake 3.20 or newer
- Icarus Verilog (`iverilog`, `vvp`) to run simulation tests
- Verilator 5.0 or newer to run simulation tests with Verilator

## Build and test

`Makefile` wraps `cmake` and `ctest`, it has 5 targets:

| Target             | What it does                              |
|--------------------|-------------------------------------------|
| `make cmake`       | configure build directory                 |
| `make build`       | configure if needed and build             |
| `make test`        | configure if needed, build and run all tests |
| `make test_parts`  | configure if needed, build and run tests of parts |
| `make test_blocks` | configure if needed, build and run tests of blocks |

Configure is needed the first time and when `CMAKE_ARGS` are given;
after that cmake re-runs itself when `CMakeLists.txt` or flists change.

Build directory is outside of the source tree, by default it is directory `build`
next to the repository directory: for repository `~/prj/dark-circuit/dark-circuit`
it is `~/prj/dark-circuit/build`.

Run all tests:

```sh
make test
```

Run from any directory:

```sh
make -C <path-to>/new2026 test
```

Use other build directory:

```sh
make test BUILD_DIR=/tmp/dc-build
```

Pass options to cmake:

```sh
make test CMAKE_ARGS="-D DARK_CIRCUIT_USE_ICARUS=ON"
```

## Simulators

Use of every simulator is controlled by cmake variable `DARK_CIRCUIT_USE_<SIMULATOR>`:

| Value  | Meaning                               |
|--------|---------------------------------------|
| `AUTO` | use it if found (default)             |
| `ON`   | require it, cmake fails if not found  |
| `OFF`  | do not use it                         |

| Simulator      | Variable                     | Test name suffix and label |
|----------------|------------------------------|----------------------------|
| Icarus Verilog | `DARK_CIRCUIT_USE_ICARUS`    | `.icarus`                  |
| Verilator      | `DARK_CIRCUIT_USE_VERILATOR` | `.verilator`               |

Verilator older than 5.0 is treated as not found (or as an error with `ON`).

Tests that need only one simulator, like tests of parts, run on the **main simulator**,
cmake variable `DARK_CIRCUIT_MAIN_SIMULATOR` selects it:

| Value       | Meaning                                              |
|-------------|------------------------------------------------------|
| `AUTO`      | first used of Verilator, Icarus (default)            |
| `verilator` | Verilator, cmake fails if it is not used             |
| `icarus`    | Icarus Verilog, cmake fails if it is not used        |

```sh
make test_parts CMAKE_ARGS="-D DARK_CIRCUIT_MAIN_SIMULATOR=icarus"
```

## Running selected tests

After `make build`, call `ctest` directly, `<build-dir>` is the build directory:

```sh
ctest --test-dir <build-dir> -N                    # list tests
ctest --test-dir <build-dir> -R gate_cell_cmos     # tests with name matching regex
ctest --test-dir <build-dir> -L icarus             # tests with label icarus
ctest --test-dir <build-dir> --output-on-failure   # show output of failed tests
```

Every test has labels: its simulator (`icarus`, `verilator`), the first directory
under `test/` (`gate`, `sim`, `part`, `block`) and, for tests deeper in `test/`,
its own directory (`carry_save_adder`).
