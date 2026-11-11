# Floating point on the integer registers: Zfinx in my RISC-V core

*November 2026. Igor Lesik. Code: [dark-circuit](../README.md), an open library of hardware
blocks and the small RISC-V cores built from them.*

Mig3, my 5-stage in-order RISC-V core, now runs all of RISC-V's single-precision floating
point: add, subtract, multiply, the four fused multiply-adds, divide, square root, compares,
min and max, sign injection, classify and the conversions, IEEE 754-exact with subnormals at
full speed. It has no floating-point registers. The F instructions read and write the same
32 x registers as everything else: that is RISC-V's Zfinx extension.

The FPU made Mig3 23 % larger and its clock did not move: 5.5 ns on SkyWater's 130 nm
process before and after. This note is how: why the integer registers, how the arithmetic
blocks are built and checked, how a 16 ns fused multiply-add fits a 5.5 ns pipeline, and how
an instruction that needs three source registers gets them from a register file with two
read ports.

## 1. Why no FP registers

RISC-V's usual F extension adds 32 floating-point registers, loads and stores for them
(FLW, FSW), moves between the two files (FMV.X.W, FMV.W.X) and its own dependence checks.
Zfinx keeps the instructions and drops the file: `fadd.s a0, a1, a2` adds two x registers.
FLW, FSW and the moves are gone (LW, SW and MV do their work); fcsr, with the rounding mode
frm and the flags fflags, stays.

For Mig3 that was an easy trade:

- **Area.** A second 32 x 32 register file with three read ports (an FMA reads three) would
  be a large block on sky130; the flops of Mig3's branch target buffer alone cost 28 % of
  the core.
- **Nothing new in the pipeline.** The x registers' forwarding and interlocks serve FP too.
  An FP result is forwarded to the next instruction like an ADD's.
- **The cores after Mig3.** One register space to rename in an out-of-order core, and small
  cores for an AI chip whose heavy math will live in vector and matrix units anyway.

Single precision only: double on RV32 under Zfinx means register pairs and six reads per
FMA, not worth it for this core.

The cost is the toolchain. gcc 12.2 accepts `-march=rv32im_zfinx`, but for C code it emits
calls to libgcc's soft-float functions; only its assembler knows the instructions. So the
FPU's tests started as assembly. clang 23 generates real Zfinx code from C, and the
project's build now probes for both toolchains and takes clang when it finds it.

## 2. The blocks: one version, checked by TestFloat

The library usually has two versions of a block: a behavioral one, fast to simulate, and a
structural one built from gates, which is what gets synthesized. For floating point I chose
one version in a family of its own, *hybrid*: the wide arithmetic (adders, the Wallace tree,
shifters, the leading-one search, wide selects, stage registers) is the library's structural
blocks, and the narrow glue (flags, special-case decisions) is plain operators. Synthesis
is controlled where it matters, and the code stays readable where it does not.

There is no behavioral twin to compare against. The model is Berkeley TestFloat, John
Hauser's generator of IEEE 754 test cases, built on his SoftFloat with its RISC-V
specialization: the canonical NaN 0x7fc00000, tininess detected after rounding, RISC-V's
results for invalid conversions. The build fetches both, generates case files for each
block, and the testbenches read them.

- **Seven blocks:** the FMA, a radix-2 divider and square root (25 clocks), compare, min and
  max, classify, sign injection, conversions both ways.
- **About a second each.** The FMA's level-1 set is 6.1 million cases; the test samples one
  in 6000, pseudo-randomly, and keeps every case with three special operands.
- **Rules that differ between ISAs are parameters,** named for the rule: what a NaN does to
  a minimum (`NAN_RULE`), what integer an invalid conversion gives (`INVALID`). RISC-V's
  choice is one value; another ISA's is another.
- **Mutants test the tests.** Each block has a list of deliberate bugs its test must catch;
  for the FMA, ten.

## 3. Pipelining a 16 ns FMA by hand

Combinational, the FMA's longest path on sky130 is 15.9 ns, three Mig3 clocks. Commercial
flows retime: put registers at the end and the tool moves them into the logic. Yosys does
not. So the FMA has a parameter STAGES, 0 to 3, and registers at fixed boundaries: after
the Wallace tree, after the adder, after normalizing.

The idiom keeps one code base for every stage count:

- **Each boundary is a struct,** `stage_boundary_tree_t` and so on, of everything that
  crosses it: data, signs, exponent, rounding mode, the special case decided from the
  operands.
- **Each boundary is a DelayLine** of depth 1, or 0, a wire. The logic after a boundary
  reads only its struct, so the arithmetic is written once and the only lines that depend
  on STAGES are three depth constants.
- **A valid bit** rides its own DelayLine of depth STAGES.

The danger in a hand pipeline is a stage that reads the value of the next operation instead
of its own: with one operation in flight it is invisible. So the test streams an operation
every clock, with the five rounding modes interleaved, so that operands, forms and modes
change from one operation to the next. Three of the FMA's mutants (a stage reading the
entering operation's rounding mode, its addend's sign, a special case taken before the last
boundary) are caught only that way.

The longest path by STAGES: 15.9, 8.5, 6.8, 5.1 ns. The last number took a structural
change: at first, three stages gave 6.4 ns, because the addend was the 25th row of the
Wallace tree and its alignment shifter sat in front of six tree layers. Moved out, aligned
while the tree reduces the product and added by one carry-save adder after it, the first
stage became 5.1 ns, under Mig3's clock.

## 4. Into the pipeline

Mig3's FPU sits in EX beside the integer multiply-divide unit. Three rules shaped it.

- **Every result through a register.** Mig3's longest path already runs from EX into ID's
  forwarding. The FPU's result goes into a register first, and the instruction completes
  the cycle after, from there: compares, min and max, conversions take 2 cycles in EX, FADD,
  FSUB and FMUL 5 (the FMA's 3 stages), FDIV and FSQRT 27. No FP block is on the core's
  critical path.
- **Start only when an interrupt can no longer come.** Mig3 takes an interrupt on the
  instruction in EX, in the first cycle it acts, and the instruction does nothing. A unit
  that started earlier would be left running for a cancelled instruction. Writing that rule
  for the FPU, I found the integer divider breaking it: it started while a load in front of
  it waited for memory, and an interrupt in the next cycle trapped a division in flight. A
  new interrupt test placed exactly there failed on an assertion, and the divider now waits
  for the same cycle as the FPU.
- **The rounding mode at run time.** An instruction's rm field can say "dynamic": round by
  frm. If frm holds one of the three values that are not a mode, that instruction traps as
  illegal, which only EX can know.

Synthesis kept me honest. The first Mig3 run with the FPU gave 6.3 ns, through the
float-to-integer conversion: it rounded with one 32-bit incrementer and then negated with a
second, in series. A negative result is -(int + r) = ~int + (1 - r), so one incrementer
does both, and the block went from 6.4 to 4.4 ns. The integer-to-float conversion then set
the path (5.7 ns), until its search for the top 1 ran beside its negation instead of after
it.

## 5. Three operands, two read ports

FMADD.S reads rs1, rs2 and rs3. The register file has two read ports, and a third would
cost a 32-way multiplexer per bit and new forwarding compares on paths that set the clock.
So rs3 comes through an existing port, in an extra cycle. Which cycle mattered more than I
expected.

- **First try: an extra cycle in ID.** In its first cycle in ID, the FMA reads rs3 through
  rs2's port, keeps it, and then reads rs1 and rs2 like any instruction. Clean, tested,
  correct. But whether the port reads rs3 depends on "is this an FMA?", decoded from ID's
  instruction word in the same cycle, and that decode landed in front of the register-file
  read, on the ID path. Mig3 measured 5.5 to 5.9 ns depending on the synthesis run.
- **What shipped: the first cycle in EX.** The FMA moves to EX with rs1 and rs2. The
  instruction behind it waits in ID anyway, because the FMA holds EX for several cycles, so
  that instruction's rs2 read in the FMA's first EX cycle would be thrown away. EX borrows
  the port for that cycle and reads rs3. Whether to borrow comes from the ID/EX register,
  known at the start of the cycle. Mig3: 5.5 ns.

Two details made it correct. Forwarding from EX is off while the port is lent, because EX
holds the FMA itself: an FMA whose destination is also its addend (`fmadd.s a6, a0, a1, a6`)
would otherwise forward its own unfinished result. And the newest writer of rs3 can only be
in the stage after EX, whose forwarding already exists, so no new interlock was needed. The
borrowed port costs the same one cycle per FMA as the extra ID cycle, without the ID path.

## 6. Checking it in the core

- **Assembly with expected registers.** One test touches every unit, the rounding modes and
  the flags; one test is the fused forms, chosen so that fusing is visible: with
  a = 1 + 2^-12, a * a - (1 + 2^-11) is exactly 2^-24 with one rounding and 0 with two.
- **The FPU against SoftFloat, from C.** One C kernel of 24 operations, compiled twice into
  one program, once as Zfinx and once as soft-float calls into SoftFloat, runs side by side
  on the core; every result and the flags of every operation must agree, in all five modes.
  Five deliberate bugs in the core's FPU logic are all caught: a compare's flag rule
  swapped, the wrong NaN rule for min and max, another ISA's integer for a NaN conversion,
  the dynamic mode ignored, the forwarding mask removed. The assembly tests miss the first
  three: they have no NaN operands where it matters. Getting it right needed strict
  floating-point compilation and a fence after each flag read: the compiler computed FMIN
  and FMAX together, and FMAX's invalid flag showed up on FMIN.

## 7. What I take from it

- **Zfinx is the right floating point for a small core.** No second register file, no new
  forwarding, and the interlocks come free; the price is in the toolchain, not the silicon.
- **One structural version plus an outside reference** beats two versions that agree with
  each other: TestFloat knows IEEE 754 better than I do.
- **A hand pipeline needs a streaming test** with changing operations, or a stage reading
  the wrong operation's value stays invisible.
- **Measure every step.** The two conversion blocks and the rs3 cycle each moved the clock,
  and each fix was a change of structure, found by synthesis, not by thinking.
- **Borrow what is idle.** The read port behind a multi-cycle instruction is free for a
  cycle; using it cost nothing on the clock.

## How I measured, and where the code is

Areas and delays are Yosys and ABC on the sky130 standard cells, typical corner, from the
project's synthesis flow: Mig3Core 335 054 um2 before the FPU, 413 427 um2 with it, 5.5 ns
both. The blocks are in `rtl/lib/numeric/fp32/*/hybrid/`, their TestFloat tests in
`test/numeric/fp32/`; the FPU is `rtl/design/mig3/mig3_fpu.sv`, the borrowed port in
`mig3_core.sv`; the core's FP tests are `test/design/mig3/fp.S`, `fp_fma.S` and
`fp_diff.c`. The decisions, with the options that lost, are in the knowledge base:
`kb/rtl/design/mig3/fp.yaml`, `fpu.yaml`, `rs3_read.yaml`, and
`kb/rtl/lib/numeric/fp32/design.yaml` and `fma_stages.yaml`.
