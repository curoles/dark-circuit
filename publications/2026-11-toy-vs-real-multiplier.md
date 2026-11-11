# Half the answers wrong: a textbook floating-point multiplier against IEEE 754

*November 2026. Igor Lesik. Code: [dark-circuit](../README.md), an open library of hardware
blocks and the small RISC-V cores built from them.*

My hardware library had a single-precision floating-point multiplier for years. It is the
one every textbook draws: multiply the two significands, add the exponents, take out the
bias, normalize by one bit. It had a test, and the test passed: 100 000 random pairs and a
list of edge cases, every product exact against a reference.

Then I needed real floating point for Mig3, my 5-stage RISC-V core, and I measured the old
multiplier against the standard's own test cases. It got 47.9 % of them wrong.

This note is about the distance between that multiplier and one that is right: what the
textbook leaves out, the bugs only a real reference finds, and what being right costs in
silicon area and in clock speed.

## 1. The toy

The old block (now `fp32/mul_teaching`, kept as a teaching example) does this:

```systemverilog
assign prod    = a_sig * b_sig;           // 24 x 24 bits
assign exp_sum = a.exp + b.exp - FP32_BIAS;
assign zero    = a.exp == 0 || b.exp == 0;
assign mant    = prod[47] ? prod[46 -: 23]
                          : prod[45 -: 23];
assign result  = zero ? '0 : {sign, exp, mant};
```

The bits below the kept 23 are dropped: the result is truncated, not rounded. An operand
with exponent 0, a zero or a subnormal, gives +0. Infinity, NaN, overflow and underflow are
not handled, and there are no flags.

Its test was honest about that. The reference computed the exact product in double
precision and truncated it the same way, and the operands were chosen so that no product
overflowed or underflowed. The test checked what the block was meant to do, and the block
did it. That is the trap: a test can only find the bugs its author can imagine.

## 2. The toy against the standard

Berkeley TestFloat (John Hauser's) generates IEEE 754 test cases with their expected results
and flags, from his SoftFloat library. Its level-1 set for `f32_mul` is 46 464 cases,
built around the boundaries where implementations go wrong. I ran the toy's RTL on all of
them, in each of the five rounding modes RISC-V has.

Wrong results, to nearest even:

- **Special operands** (NaN, infinity, zero): 4 307 of 4 642. Every zero product comes out
  +0, so -0 is lost; NaN and infinity become arbitrary numbers.
- **Subnormal operands:** 2 742 of 3 065.
- **Products that must underflow:** all 1 735.
- **Products that must overflow:** 2 799 of 2 824.
- **Ordinary products,** normal operands and a normal result: 11 894 of 34 198 (34.8 %),
  each wrong by exactly one unit in the last place.

Over all five modes: 111 293 wrong of 232 320, 47.9 %. And 82 % of the cases expect a flag,
mostly "inexact", which the toy can not raise at all.

One mode is different. Rounding toward zero, the toy gets every ordinary product right: 0
wrong of 34 183. Truncation is round-toward-zero. So the textbook multiplier is exactly one
of the standard's five rounding modes, for normal numbers only, and wrong almost everywhere
else.

A fair caveat: level 1 is dense in boundary values on purpose. For numbers from a real
program, the 34.8 % of ordinary products is the better guide. One product in three still
differs from what any IEEE machine gives.

## 3. What right takes

The replacement is `Fp32Fma`, a fused multiply-add: a * b + c with one rounding. RISC-V's F
extension has the fused forms (FMADD.S and three sign variants), and FADD, FSUB and FMUL are
its special cases (the multiplier gets 1.0 for an add; a multiply gets no addend). What it
does that the toy does not:

- **Rounding, five ways.** The exact result keeps a guard bit and a sticky bit (the OR of
  everything below), and the rounding mode decides: to nearest with ties to even or away
  from zero, toward zero, up, down. Overflow, underflow and inexact come out of the same
  step. RISC-V detects tininess after rounding, so underflow depends on the rounded value.
- **Subnormals at full speed.** A subnormal significand goes into the multiplier as it is;
  the normalization after the sum moves it. No slow path: on some x86 processors a
  subnormal operand still costs a microcode assist (Daniel Lemire wrote about it recently),
  which is exactly what an AI datapath full of tiny values can not afford.
- **Special cases by the ISA's rules.** A NaN result is the canonical NaN 0x7fc00000.
  Infinity times zero is invalid, even when the addend is a quiet NaN: RISC-V's choice,
  where other ISAs differ. Where ISAs differ, the library makes the rule a parameter, so the
  block does not bake one architecture in.
- **The sign of zero.** A multiply has no addend, but it can not be treated as adding +0:
  -1 x +0 + 0 is +0, while -1 x +0 must be -0. The missing addend is a zero with the
  product's sign.
- **The flags,** all five, exact.

Inside, the product (48 bits) and the addend share one field. The addend is placed above
the product and shifted right by the exponent difference; bits that fall off the bottom are
ORed into bit 0, the jam. The sum is found by a Wallace tree of the partial products, a
carry-save adder for the addend and one Kogge-Stone adder; a priority encoder finds the top
1, a shifter normalizes, and one rounding block finishes.

## 4. The bugs only the reference found

I wrote the FMA carefully and tested it against TestFloat from the first day. TestFloat
still found three bugs I would not have looked for:

- **The exponent after a clamp.** When the addend is far larger than the product, the shift
  is clamped and the field counts from the addend's exponent, not the product's. I had
  forgotten to switch the exponent base.
- **A zero addend that moved the field.** The clamp must not fire for a zero addend (or a
  multiply, which has none): a zero has no exponent worth following.
- **The sticky bit that became a guard bit.** A normal number times the smallest subnormal
  has a product only 24 bits long, sitting low in the field. Normalization then shifts so
  far that bit 0, the jam, lands where the guard bit belongs: an addend bit that was lost
  decides a rounding as if it were half an ulp. The fix was one bit: the field grew to 77
  bits, with bit 1 always 0, so the jam can never become the guard.

And the tests had bugs too. TestFloat's level-1 set for `f32_mulAdd` is 6.1 million cases,
too many for a one-second test, so the test samples them. My first sampler took every
6000th case; a deliberately broken FMA (a mutant) survived it, because the regular stride
kept stepping over the cases that mattered. A pseudo-random pick fixed that, and every case
with three special operands is always kept. Later, in the divider's test, the generator's
low random bits turned out to repeat with a short period, and not one x/0 case was ever
picked; picking by the high bits fixed it.

That is why each block's tests are checked by mutants: small deliberate bugs (lose the jam,
forget the zero's sign, swap a rounding direction) that the tests must catch. The FMA's
tests catch all ten of its mutants. A test that has never failed has not shown it can.

## 5. What right costs

On SkyWater's 130 nm open process (Yosys and ABC, typical corner):

- **The toy,** combinational: 24 905 um2, 5.8 ns.
- **The FMA,** combinational: 46 846 um2, 15.9 ns.

About twice the area, but not all of it is correctness: the FMA also adds, subtracts and
fuses. The time is the bigger problem: 15.9 ns is three times my core's clock.

Commercial flows retime: you put registers at the end of a block and the tool moves them
into the logic. Yosys does not, so the FMA takes its stages by hand: a parameter STAGES puts
registers at fixed boundaries (after the tree, after the adder, after normalizing), each
boundary a struct of everything that crosses it, and the arithmetic is written once. Its
longest path by STAGES: 15.9, 8.5, 6.8 and 5.1 ns.

The last step came from a structure change, not a register. With three stages the first one
was 6.4 ns: the addend was the 25th row of the Wallace tree, so its alignment shifter sat in
front of six tree layers. Moved out of the tree, aligned while the tree reduces the product
and added by one carry-save adder after it, the stage became 5.1 ns. The toy's own
three-stage version runs at 5.2 ns, so the honest unit pipelines to the same clock.

## 6. In the core

Mig3 runs floating point on its integer registers (RISC-V's Zfinx: no separate FP register
file). Two details from putting the FMA there:

- **A register before the forwarding.** Every FP result goes through a register before
  other instructions can use it, so no FP logic lands on the core's longest path. FADD.S
  takes 5 cycles in EX, the core's clock stays at 5.5 ns.
- **The third operand through a borrowed port.** FMADD.S reads three registers; the
  register file has two read ports. In the FMA's first cycle in EX, the instruction behind
  it is stalled anyway, so EX borrows that instruction's read port for one cycle to read the
  addend.

The last check was the strongest. The same C kernel, compiled twice into one program, once
as FPU instructions and once as soft-float calls into SoftFloat, runs on the core side by
side, and every result and every flag must agree, bit for bit, in all five rounding modes.
The compiler arranges the FPU's instructions in ways I would not write by hand. Even this
test had a trap: the compiler computed FMIN and FMAX together, and FMAX's invalid flag
showed up on FMIN, until each flag read was fenced.

## 7. What I take from it

- **A test can only check what its author imagined.** The toy passed its own test for
  years. A reference written by someone else, built around the boundaries, is what finds
  the rest.
- **The textbook multiplier is one rounding mode.** Truncation is round-toward-zero; the
  other four modes, the specials, subnormals and flags are most of the work.
- **The nastiest bugs live where two features meet:** a subnormal product and the sticky bit,
  a missing addend and the sign of zero.
- **Test the tests.** A sampler can skip exactly the cases that matter; a mutant shows it.
- **Being right costs about twice the area here, and no clock,** once the stages are placed
  by hand and the structure is chosen with the timing in mind.

## How I measured, and where the code is

The toy's numbers come from its RTL (`rtl/lib/numeric/fp32/mul_teaching/comb`) simulated on
TestFloat's complete level-1 `f32_mul` set (`testfloat_gen -level 1`, the five rounding
modes, tininess after rounding), in Verilator. The areas and delays are Yosys and ABC on the
sky130 standard cells, typical corner, from the project's synthesis flow. The FMA is
`rtl/lib/numeric/fp32/fma/hybrid/fp32_fma.sv`, its test `test/numeric/fp32/fma`, its mutants
`kb/test/numeric/fp32/fma/mutants.yaml`; the stages are `kb/rtl/lib/numeric/fp32/fma_stages`.
The core's side is `rtl/design/mig3/mig3_fpu.sv`, the differential test
`test/design/mig3/fp_diff.c`, and the decisions behind them are in `kb/rtl/design/mig3/`.
