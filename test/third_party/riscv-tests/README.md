# riscv-tests

THIS DIRECTORY IS GENERATED, DO NOT EDIT MANUALLY!
Copied by tools/riscv_tests.sh from https://github.com/riscv-software-src/riscv-tests.git
commit d7e86f701b929b5d801f8cda1a4871ab05f452bb (env: riscv-test-env commit 6de71edb142be36319e380ce782c3d1830c65d68),
suites: rv32ui rv32mi.

Self-checking RISC-V ISA tests, BSD license (LICENSE, env/LICENSE). They run with
their standard environment env/p (riscv_test.h): a test ends with a store to the
word tohost, 1 is pass, (case << 1) | 1 is a failed case.
