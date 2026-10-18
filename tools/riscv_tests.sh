#!/bin/bash
# Copy RISC-V ISA tests from riscv-tests (BSD license) into test/third_party/riscv-tests.
#
# Usage: tools/riscv_tests.sh [suite ...]    default: rv32ui
#
# Clones riscv-tests at COMMIT into a temporary directory and copies, keeping the
# directory layout of riscv-tests:
# - isa/<suite>/*.S for every suite;
# - the isa/rv64*/ sources they include (rv32ui/add.S includes ../rv64ui/add.S);
# - isa/macros/scalar/test_macros.h and LICENSE;
# and writes README.md. Not copied: env/ (every design has its own riscv_test.h),
# Makefiles. Needs git. Run it again only to add suites or to move to a newer COMMIT.
set -euo pipefail

REPO=https://github.com/riscv-software-src/riscv-tests.git
COMMIT=d7e86f701b929b5d801f8cda1a4871ab05f452bb
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/test/third_party/riscv-tests

if [ $# -gt 0 ]; then SUITES=("$@"); else SUITES=(rv32ui); fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

git clone --quiet "$REPO" "$TMP/riscv-tests"
git -C "$TMP/riscv-tests" checkout --quiet "$COMMIT"
SRC=$TMP/riscv-tests

mkdir -p "$OUT/isa/macros/scalar"
cp "$SRC/LICENSE" "$OUT/LICENSE"
cp "$SRC/isa/macros/scalar/test_macros.h" "$OUT/isa/macros/scalar/"

count=0
for suite in "${SUITES[@]}"; do
    mkdir -p "$OUT/isa/$suite"
    for test in "$SRC/isa/$suite"/*.S; do
        cp "$test" "$OUT/isa/$suite/"
        count=$((count + 1))
        # Sources included from other suites, like #include "../rv64ui/add.S".
        for inc in $(sed -n 's|^#include "\.\./\([^"]*\)"|\1|p' "$test"); do
            mkdir -p "$OUT/isa/$(dirname "$inc")"
            cp "$SRC/isa/$inc" "$OUT/isa/$inc"
        done
    done
done

{
    echo "# riscv-tests"
    echo ""
    echo "THIS DIRECTORY IS GENERATED, DO NOT EDIT MANUALLY!"
    echo "Copied by tools/riscv_tests.sh from $REPO"
    echo "commit $COMMIT, suites: ${SUITES[*]}."
    echo ""
    echo "Self-checking RISC-V ISA tests, BSD license (LICENSE). Every test includes"
    echo "riscv_test.h, the environment of the design that runs it; for Mig1 it is"
    echo "test/design/mig1/riscv_test.h."
} > "$OUT/README.md"

echo "riscv_tests: copied $count tests of ${SUITES[*]} into ${OUT#"$ROOT"/}"
