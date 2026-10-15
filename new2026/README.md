# DARKCIRCUIT

## Requirements

- CMake 3.20 or newer
- Icarus Verilog (`iverilog`, `vvp`) to run simulation tests

## Build and test

`Makefile` wraps `cmake` and `ctest`, it has 3 targets:

| Target       | What it does                              |
|--------------|-------------------------------------------|
| `make cmake` | configure build directory                 |
| `make build` | configure if needed and build             |
| `make test`  | configure if needed, build and run all tests |

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

| Simulator      | Variable                  | Test name suffix and label |
|----------------|---------------------------|----------------------------|
| Icarus Verilog | `DARK_CIRCUIT_USE_ICARUS` | `.icarus`                  |

## Running selected tests

After `make build`, call `ctest` directly, `<build-dir>` is the build directory:

```sh
ctest --test-dir <build-dir> -N                    # list tests
ctest --test-dir <build-dir> -R gate_cell_cmos     # tests with name matching regex
ctest --test-dir <build-dir> -L icarus             # tests with label icarus
ctest --test-dir <build-dir> --output-on-failure   # show output of failed tests
```
