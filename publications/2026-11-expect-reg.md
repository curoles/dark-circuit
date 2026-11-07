# EXPECT_REG: register expectations that live in the test binary of self-checking assembly tests

*November 2026. Igor Lesik. Code: [dark-circuit](../README.md), an open library of hardware
blocks and the small RISC-V cores built from them.*

When you build your own CPU, the first tests are small assembly programs: add two numbers,
load a word, take a branch. Each test has to say whether the CPU got it right. The usual way
is to let the program check itself: compute, compare with the expected value, branch to a
"fail" label if they differ. That asks the CPU under test to grade its own exam, with the
very instructions you are trying to test. This note describes the small trick my cores use
instead: the expected register values are a table in the test binary itself, right after the
instruction that stops the CPU, and the testbench, not the CPU, compares them. Ten lines of
assembly and twenty lines of SystemVerilog.

The cores are Mig1, Mig2 and Mig3, 5-stage in-order RISC-V cores (RV32IM and more) that run
on Verilator. Mig1 started as a 2-stage RV32I core, and its first tests had to work before
its branches did.

## 1. The CPU should not grade its own exam

A self-checking test in the style of riscv-tests looks like this (simplified):

```asm
    li    x1, 5
    li    x2, -3
    add   x3, x1, x2
    li    x7, 2         # the expected value
    bne   x3, x7, fail  # the CPU compares and branches
```

It is a fine approach for a CPU that mostly works. On one that does not, it fails in
unhelpful ways:

- a broken `bne` can skip every check, and the test passes;
- a broken `li` (an `addi` and maybe a `lui`) puts a wrong expected value in `x7`;
- a CPU that cannot branch yet cannot run the test at all;
- when it fails, it tells you "test case 7 failed", and you go look for which register held
  what.

What I wanted: the test only computes; something outside the CPU knows what the registers
must hold at the end, and checks.

## 2. The macro

Each test program defines one macro:

```asm
    .macro EXPECT_REG r, value
    .word \r, \value
    .endm
```

It emits two words: a register number and the value that register must hold. A test ends
with the instruction that halts the core (an `ebreak` that the testbench's core halts on),
followed by a table: the number of entries, then the pairs.

```asm
_start:
    addi  x1, x0, 5
    addi  x2, x0, -3
    add   x3, x1, x2
    sub   x4, x1, x2
    slt   x6, x2, x1     # -3 < 5 signed
    sltu  x7, x2, x1     # 0xfffffffd < 5 unsigned
here:
    auipc x24, 0
    ebreak               # the core halts here

    .word (expect_end - expect) / 8
expect:
    EXPECT_REG 3,  2
    EXPECT_REG 4,  8
    EXPECT_REG 6,  1
    EXPECT_REG 7,  0
    EXPECT_REG 24, here  # a label: the assembler fills in its address
expect_end:
```

The CPU never executes the table: it halts on the `ebreak` before it. The values are
assembler expressions, so the assembler does the arithmetic for simple cases
(`0xfffffffd >> 28`, `5 << 31`) and fills in addresses from labels. That last part turned out
to be the most useful: a test can say "mepc must be the address of instruction `c10`" as
`EXPECT_REG 24, c10`, and it stays right when code is added above `c10`.

## 3. The testbench side

The testbench runs the program until the core halts, then reads the table from the program's
memory, at the address right after the halting instruction (which it knows: the core reports
where it halted):

```systemverilog
    task automatic check_regs;
        word_t a, n, r, value, got;
        a = halt_pc + 4;
        n = imem_word(a);
        if (n == 0 || n > 32)
            $fatal(1, "+expect_regs: %0d entries at %h: no table after the halting insn?",
                   n, a);
        repeat (n) begin
            a = a + 4;  r     = imem_word(a);
            a = a + 4;  value = imem_word(a);
            if (r != 0 && !written[r])
                $fatal(1, "x%0d was never written, expected %h", r, value);
            got = (r == 0) ? '0 : shadow[r];
            if (got !== value)
                $fatal(1, "x%0d is %h, expected %h", r, got, value);
        end
    endtask
```

Two details matter:

- **The registers it compares are a shadow copy built from the retire trace**, not the core's
  own register file. Every instruction that retires reports the register it wrote and the
  value (the RVFI convention); the testbench keeps its own 32 registers from that. So the
  check sees exactly what the core *reported* as done, and a value that sits in the register
  file but was never retired (or retired wrong) does not pass.
- **A register in the table that was never written fails**, even if the expected value is 0.
  Otherwise "x5 must be 0" passes on a core that never executed the instruction that writes
  x5, because registers start at 0.

The check is switched on per test with a plusarg, `+expect_regs`, and a failure stops the
simulation with `$fatal`, so the test fails by its exit code. A missing table (the `n == 0`
case) is an error too, not a pass.

## 4. Examples from the real tests

A first test of a new core (Mig1's `alu.S`) is straight-line code: every register gets a
result, and the table lists them. No branch needed anywhere.

An interrupt test (Mig3's `irq.S`) places interrupts on chosen instructions and lets the
handler record what happened in a few registers: `s6` collects errors (the handler ORs in
any difference it sees in `mcause`, `mtval`, `mstatus`), `s7` counts interrupts, `s8` keeps
the last `mepc`. The table is short and says a lot:

```asm
    EXPECT_REG 22, 0     # s6: no error seen by the handler
    EXPECT_REG 23, 10    # s7: 10 interrupts
    EXPECT_REG 24, c10   # s8: the last one was taken on instruction c10
```

A device test (Mig3's `plic.S`) checks an interrupt controller's registers through the
addresses of a header generated from the hardware's configuration, and the expected values
come from the same header:

```asm
#include "mig3_config.h"
    ...
    # a priority register's width
    EXPECT_REG 9,  MIG3_PLIC_PRIO_MAX
    # the enable bits of the sources
    EXPECT_REG 19, (1 << (MIG3_PLIC_SOURCES + 1)) - 2
```

Change the number of interrupt sources in the configuration, and the test's expectation
follows.

## 5. What it does not do

- **It checks the end state only.** A test keeps its results in distinct registers (there
  are 31), or folds many checks into one: the "OR every difference into s6" idiom above
  turns any number of comparisons into one expected 0. Those comparisons run on the CPU, so
  they come after its basic instructions are trusted.
- **Memory results need a load** into a register, or another check (my testbench has
  `+expect_mem_unchanged`, and a retire checker that compares every load and store with a
  model of the memory).
- **The expected values are only as right as the person or the assembler that wrote them.**
  For `add` the assembler is a perfectly good reference model; for `mulh` of two negative
  numbers you compute the constant yourself, and you can get it wrong.

## 6. How it compares

- **Self-check in the program (riscv-tests).** The CPU under test decides pass or fail,
  then writes to `tohost`. It needs branches, compares and a reporting convention. Weak
  spot: a broken CPU can grade itself wrong.
- **Signature (riscv-arch-test).** After the run, a script compares a dumped memory region
  with a reference model's signature (Sail, Spike). Weak spot: the setup, and it sees only
  what ends up in memory.
- **Co-simulation (Spike in lock step, RVFI with riscv-formal).** An instruction set
  simulator or formal checks judge every instruction. It needs the most infrastructure,
  and that is also its weak spot.
- **EXPECT_REG.** The testbench decides, from a table in the binary. It needs a halting
  instruction and a retire trace. Weak spot: it checks the end state only.

EXPECT_REG sits at the cheap end: no reference model, no extra files, and it does not depend
on the CPU being right about anything but the instructions under test and the halt. I use it
next to the heavier checks, not instead of them: the same tests also run with a retire
checker (every retired instruction against the program and a memory model), cycle ceilings
for performance, and the riscv-tests suite in its own self-checking style. Each catches a
different kind of mistake.

## 7. When to move on

Once a core passes riscv-tests and runs real programs, most new bugs are in timing (a
forwarding path, a stall) rather than in what one instruction computes, and those are better
caught by a checker that looks at every instruction (a retire checker, or co-simulation).
EXPECT_REG stays useful for one thing it does best: a short, readable statement of what a
directed test must leave behind, written right next to the code that produces it.

The macro, the tests and the testbench are in the repository: `test/design/mig1/alu.S`,
`test/design/mig3/irq.S`, `test/design/mig3/plic.S`, and the `check_regs` task in
`test/design/mig3/tb/tb_mig3.sv`. The knowledge-base record behind this note is
`kb/test/design/mig1/expect_regs.yaml`.
