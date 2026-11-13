# Four pieces of one array: a packed multiplier for int8 dot products

*November 2026. Igor Lesik. Code: [dark-circuit](../README.md), an open library of hardware
blocks and the small RISC-V cores built from them.*

An int8 neural-network layer is mostly one operation: multiply four bytes by four bytes and
add the four products to a running sum. RISC-V's draft packed SIMD extension, P, has it as
PM4ADDA.B. It also has byte products, 16 x 16 products and their high halves, Q15 products
with rounding, and halfword dot products. I wanted all of them from one multiplier, small
enough for Mig3, my 5-stage RISC-V core, and fast enough for its 5.5 ns clock on
SkyWater's 130 nm process.

The first version was slower than a plain multiplier. The one in the core is faster than
it, and smaller. This note is how it got there, one measurement at a time.

## 1. Not the core's multiplier

Mig3 already multiplies: MUL is one cycle in EX. Putting lanes into that multiplier would
save about 24 000 um2, but its masks would sit on the core's longest path, which has no
margin left. And the cores ahead want them apart anyway: a 64-bit core needs a 64 x 64
scalar multiplier, and a vector lane needs the packed one alone. So PackedMul is a block
of its own.

## 2. One lane is four bytes multiplied by four bytes

A 16-bit lane, a = {ah, al} and b = {bh, bl}, multiplies by long multiplication: 16 rows,
row j holding a & b[j], shifted by j. The 16 x 16 array splits into four 8 x 8 quadrants:

```
            al          ah
         +---------+---------+
    bl   | LL  w 0 | HL  w 8 |   rows 0-7
         +---------+---------+
    bh   | LH  w 8 | HH w 16 |   rows 8-15
         +---------+---------+
```

```
a * b = LL + (HL + LH) << 8 + HH << 16
```

Every instruction is a choice of quadrants:

- **A 16 x 16 product:** all four.
- **A byte product** (PMUL.H.B00 and friends): one piece, the chosen bytes in LL's place.
- **A byte dot product** (PM4ADD.B): the two diagonal pieces, LL and HH, both at weight 0,
  so one lane gives al*bl + ah*bh, and two lanes give the four products.
- **A halfword dot product** (PM2ADD.H): two 16 x 16 products added.

One array of 16 x 16 bits per lane serves them all. A 16 x 16 lane multiplier with a
separate dot-product tree beside it would need about 1.5 times the partial products.

## 3. First try: pieces with their own signs

Signs are the hard part. In a signed byte the top bit weighs -128, and each piece may be
signed or unsigned on each side. My first version built every piece as its own small
multiplier, a library part, MulRows, using the sign correction of the core's Int32Mul:
two complemented rows, ones above them, and a constant.

The part's test failed first. -128 * -128 in 32 bits gave 0xffff4000, not 0x00004000.
Int32Mul's rows leave out a 1 << 16 for two negative operands, which is harmless only when
the product is kept in exactly 16 bits; MulRows adds it when the result is wider.

Then the synthesis, two 16-bit lanes:

- **PackedMul from MulRows pieces:** 5.2 ns, 30 654 um2, 44 rows per lane.
- **Plain 16 x 16 lanes, bytes sign-extended into them:** 4.6 ns, 27 093 um2, but no byte
  dot product, because the diagonal pieces are not separate there.
- **Int32Mul, for scale:** 4.5 ns, 45 385 um2.

Four multipliers in one place cost more rows than the one array they came from.

## 4. Baugh-Wooley: signs as inverted bits and one constant

The fix is older than the problem. A partial-product bit that involves a sign bit has a
negative weight. A negative bit can be written as an inverted bit minus one:

```
-t = (1 - t) - 1 = ~t - 1
```

So each such bit is inverted in place, and every "minus one" goes into a single constant.
In one lane, the inverted bits are exactly where a signed byte's sign bit meets the other
byte, and the constant is a function of the mode and the sign flags only:

```systemverilog
// one signed byte: its sign bit times
// every bit of the other byte
if (fa && fb) w = (1 << 8) * ((1 << 7) - 1);
if (fa ^  fb) w = (1 << 7) * ((1 << 8) - 1);
// constant row = -(sum of w at the
// pieces' weights), modulo 2^32
```

The pieces fold back into the plain array's 16 rows, plus one constant row: 17 rows per
lane instead of 44. 4.4 ns and 24 106 um2, faster and smaller than both the plain lanes
and the first version.

## 5. Dot products: switch parts off to see what costs

The dot products came next: the two lanes of a 32-bit group added, an accumulator on top.
The first version masked every partial-product bit by its piece, moved HH to weight 0 with
a select on its rows, and added the lanes and the accumulator after the lanes' trees.
6.3 ns.

A number like that says nothing about where the time goes, so I synthesized it again with
parts switched off, one at a time:

- **Everything:** 6.3 ns.
- **Products only:** 4.6 ns.
- **Dot products only:** 6.1 ns.
- **Dot products without the byte dot product:** 5.6 ns.
- **Dot products without the accumulator:** 5.8 ns.

Read together: adding the lanes after their trees cost about 1.2 ns, three levels of full
adders; the masks and the move about 0.5; the accumulator's own level 0.3. Three changes
followed:

- **Select at the operands, not the products.** Rows 0 to 7 multiply a 16-bit copy of a,
  rows 8 to 15 a 24-bit copy, shifted by j - 8. The mode decides what goes into the
  copies: a piece whose byte is 0 there gives 0, and HH lands at weight 0 when ah sits at
  the bottom of the 24-bit copy. No bit is masked or moved after the AND gates.
- **Stay in carry-save.** Each lane's tree ends in two rows, sum and carry. The dot
  product puts the two lanes' four rows into one small tree and one adder, instead of two
  lane adders and a third one after them.
- **The accumulator is a row.** It goes into the first lane's tree as row 18. A Wallace
  tree for 18 or 19 rows is no deeper than one for 17, so the row is free.

5.8 ns: much better, and still above the core's clock.

## 6. One register, and the rounding as a row

The multiplies were always meant to go through a result register, as the FPU's do, so
PackedMul got a STAGES parameter. With STAGES 1, a register sits after the lanes' trees,
holding their sum and carry rows; the adders and the dot product's tree come in the next
clock. 3.4 ns, 35 922 um2, of which the register is about 350.

Then the rounding: P's rounded high halves add 1 << 15 to every lane, Q15 adds 1 << 14. My
first version added it into the constant row, which put an adder in front of the tree:
4.2 ns. As a row of its own, 19 rows in a tree no deeper than 17's: 3.9 ns, 36 870 um2.
The same lesson as the accumulator: a row is cheap, an adder is not.

## 7. Tested as a block, measured in the core

The test compares every mode with the lane products: every byte pair in every position
and sign mode, 16 x 16 edge values in every pair, 30 000 random words, accumulators that
wrap, rounding at a random position. The full test takes about 6 s, too slow to run
whenever anything changes, so it has a quick level too: 0.4 s at effort 0 (16 values of
b's bytes), which still catches all ten mutants, deliberately broken copies of the block.

In Mig3, the multiplies take 3 cycles in EX, 4 for the accumulating forms, which read rd
as a third operand through a read port borrowed from ID. The core's clock stayed at 5.5 to
5.6 ns, with the longest path in the core's own forwarding logic, not in the multiplier.
An int8 fully connected layer runs 3.6 times faster than plain C on the same core.

## 8. What I take from it

- **Rows are cheap, adders are not.** Anything that can be one more row of a tree
  (accumulator, rounding, sign constant) is nearly free; anything that adds before or
  after the tree costs a carry chain.
- **Choose at the operands.** Selecting what goes into the AND gates costs one mux level
  at the start; masking the products costs it on 512 bits in the middle.
- **Switch parts off.** One synthesis per removed feature turned 6.3 ns into a list of
  costs, and the list into three changes.
- **The obvious structure was the expensive one.** Four multipliers for four pieces cost
  more than the one array they are pieces of.
- **Let the test catch the arithmetic.** The missing 1 << 16 lived in a correction that
  is right in one width and wrong in another; only a test at the wider width saw it.

## How I measured, and where the code is

Areas and delays are Yosys and ABC on the sky130 standard cells, typical corner, from the
project's synthesis flow; ABC varies by about half a nanosecond between near-identical
designs, so differences below that are noise. The block is
`rtl/lib/numeric/packed/mul/hybrid/packed_mul.sv` (hybrid: the trees and adders are library
blocks, the partial-product bits, selects and constants are glue), MulRows is
`rtl/lib/part/mul_rows.sv`, the tests are `test/numeric/packed/mul/` and
`test/part/mul_rows/`, and the core's unit is `rtl/design/mig3/mig3_packed_mul.sv`. The
decisions, with the options that lost, are in `kb/rtl/lib/numeric/packed/mul.yaml` and
`kb/rtl/design/mig3/packed_mul.yaml`.
