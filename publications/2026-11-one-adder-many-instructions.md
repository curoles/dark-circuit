# One adder, many instructions: packed SIMD in my RISC-V core

*November 2026. Igor Lesik. Code: [dark-circuit](../README.md), an open library of hardware
blocks and the small RISC-V cores built from them.*

Mig3, my 5-stage in-order RISC-V core, now runs 32 instructions of RISC-V's packed SIMD
extension, P: add and subtract, saturating add and subtract, minimum and maximum, and
shifts, on four 8-bit or two 16-bit lanes of an ordinary 32-bit register. Every one takes a
single cycle in EX, like an ADD. The packed unit costs about 1.6 % of the core's area, and
the clock stayed at 5.5 ns on SkyWater's 130 nm process, though the last step used up the
margin, which is part of the story.

This note is how: one lane-cut adder shared by three kinds of instruction, flags kept per
byte, a shifter that needs no lanes at all, and the rule that saved the timing more than
once: do not wait for the sum.

## 1. Why P, and which P

P is a draft: version 0.6, in review, not ratified. I follow it closely anyway, because
the point is a core someone could use with standard software, and because the hardware
inside it is what a vector lane needs later: an adder whose carry stops at lane
boundaries, saturation, lane compares, a lane-partitioned multiplier, an int8 dot product.

- **Encodings from the tables, not typed by hand.** The instruction encodings come from
  riscv-opcodes, the machine-readable tables, generated into a SystemVerilog package. A
  newer draft is a regeneration.
- **Two sources that must agree.** The decode test is assembled by clang 23 (P is an
  experimental extension there) and decoded by the RTL built from riscv-opcodes. If the two
  ever disagree on an encoding, the test fails.
- **A subset chosen by use.** The full draft is several hundred instructions. The order
  follows what an int8 neural-network layer needs; more on that below.

## 2. The lane-cut adder

A packed add is an ordinary add whose carry does not cross from one lane into the next.
Software people know the trick as SWAR, SIMD within a register:

```c
/* four byte lanes, no carry between them */
uint32_t padd_b(uint32_t a, uint32_t b) {
    uint32_t low = (a & 0x7f7f7f7f)
                 + (b & 0x7f7f7f7f);
    return low ^ ((a ^ b) & 0x80808080);
}
```

In hardware the cut goes into the adder itself. The library's Kogge-Stone adder got a
segmented sibling: a bit marked as a segment start takes the carry in, as bit 0 does,
instead of the carry from the bit below. PackedAdd marks the low bit of every lane,
depending on the lane width. Subtraction is a + ~b + 1 in every lane: b inverted, and the
carry in is 1 at each lane's start.

- **The cut is cheap.** 1.5 ns and 2537 um2 for 32 bits, against 1.3 ns and 1783 um2 for
  the plain adder: about one gate of delay and 42 % more area. The same adder with every bit
  cuttable is 1.9 ns; cutting only at 8, 16 and 24 lets synthesis fold the rest away.
- **Flags per byte, not per lane.** PackedAdd gives the carry out and the signed overflow
  at the top bit of every byte. A lane's flags are those of its top byte. Per byte, a flag
  means the same thing in every lane width and in a 64-bit word; a helper spreads a lane's
  flag over its bytes, and only the users that need it pay for it. A plain PADD does not.

## 3. Saturation: do not wait for the sum

PSADD.B adds four bytes and clamps each one that overflows: 127 + 1 stays 127, and RISC-V's
vxsat flag records that something was clamped. Saturation is a block of its own after
PackedAdd: it takes the sum and the flags and puts every lane that overflowed at its limit.

My first version took the signed limit from the sum's sign. If the wrapped sum is negative,
the true result was positive, so clamp to the largest positive. Correct, and 3.0 ns for
add plus saturate. But the sum's top bit is the very last thing an adder produces.

There is an earlier signal with the same answer. A signed add can only overflow when both
operands have the same sign, and a subtract only when they differ. Either way, whenever a
lane overflows, the true result has the sign of the first operand, a. So the limit comes
from a, which is there before the adder starts:

```systemverilog
// per byte: s is a's sign in this lane,
// top marks the lane's top byte
limit = uns ? {8{!sub}}
            : {s ^ !top, {7{!s}}};
```

Only the select now waits for the adder. Add, saturate and the final pick of the result:
2.7 ns.

## 4. Minimum and maximum from the carry alone

PMIN and PMAX pick a or b in every lane. The adder computes a - b, and the compare needs
less than one would think:

- **Unsigned:** a < b exactly when the lane's subtraction has no carry out.
- **Signed, signs differ:** a < b exactly when a is negative.
- **Signed, same sign:** the unsigned answer.

```systemverilog
less = (signed && sa != sb) ? sa : !co;
```

No sum, no overflow flag, just the carry and the operands' sign bits; the select's inputs
are a and b themselves, there from the start. Add plus min/max: 2.2 ns. One adder now
serves wrapping, saturating and min/max instructions; each is a small block on its flags,
and the instruction picks the result.

## 5. Shifts: one shifter, no lanes

Packed shifts look like they need a shifter per lane. They do not, because every lane
shifts by the same amount (an immediate, or rs2[4:0]). Shift the whole word, and the bits
that cross from one lane into the next land exactly on the bits the shift vacated there. A
mask per lane clears them, and an arithmetic right shift fills them with the lane's sign.

The mask depends only on the amount, the direction and the lane width, so it is computed
beside the shifter, not after it. PackedShift: 1.5 ns and 4088 um2; the plain 32-bit
shifter inside it, alone, 1.7 ns and 2328 um2. The masks cost area, not time.

## 6. Into the core

Mig3 decodes each P instruction into a small control struct: which block's result rd
takes (add, saturate, min/max, shift), subtract or not, signed or not, the lane width. The
packed unit sits in EX beside the ALU:

```
rs1, rs2 -> PackedAdd -> sum, carry, overflow
   -> PackedSaturate -> saturated
   -> PackedMinMax   -> min/max
rs1, amount -> PackedShift -> shifted
op picks one of the four -> rd
```

Three details from the integration:

- **The interlock needed only two opcodes.** Mig3 decides which registers an instruction
  may read from its opcode alone, not from the full decode, which grows with every
  extension. P lives in OP-32 and OP-IMM-32, free on RV32; adding them to the "reads rs1
  and rs2" rule was the whole change.
- **vxsat is set when the instruction completes,** like the FPU's flags, and stays set
  until written. The tests check the edges: lanes that reach a limit exactly (-128,
  -32768) do not set it, and a wrapping PADD that overflows does not either.
- **The assembler changed my test.** With P enabled, clang assembled `li x8, 0x00010001`
  as P's packed load-immediate, PLI.H, an instruction Mig3 does not have yet. The test
  trapped as illegal; it now builds the constant with LUI and ADDI.

## 7. The clock, chunk by chunk

Every step was synthesized, and I checked which path was longest, not just how long:

- **Add and subtract:** 5.4 ns, the longest path in the FPU's third-operand read, as before.
- **Saturating:** 5.3 ns, the longest path in the FMA.
- **Min and max:** 5.4 ns, the longest path in the caches.
- **Shifts:** 5.5 ns, the longest path from EX's result through forwarding into ID.

The last one needed a second look, because the packed result feeds exactly that path. The
same run with the packed unit tied off gives 5.4 ns on the same path: it is the core's own
forwarding path, and P is 0.1 ns over it, inside the half-nanosecond that ABC, the mapper,
varies between near-identical designs. Within the rule, but the margin is gone. Further
one-cycle packed instructions would need a result register, as the FPU uses; the
multiplies and dot products were planned that way from the start.

## 8. Is averaging even used?

P has averaging adds, PAADD and friends, and I had them next in line. Then the question
came: does any software use them? Codecs, image blending and audio mixing average pairs,
but with rounding (x86's PAVGB, Arm's URHADD), while P's averages truncate; and no int8
neural-network layer averages pairs. So the order now follows one kernel, to come with the
dot products: an int8 fully connected layer, as TensorFlow Lite Micro runs it, written
twice, in plain C and with P, run side by side on the core with every output compared and
the cycles of both printed. Averaging waits until something asks for it.

## 9. What I take from it

- **Do not wait for the sum.** The sum's top bit is an adder's last output; the operands'
  signs and the carries often carry the same answer earlier. It saved 0.3 ns in
  saturation and kept min/max at 2.2 ns.
- **One adder, small blocks on its flags.** Each operation stays a block of its own,
  tested on its own, sharing the adder in the core.
- **Look at the path, not the number.** 5.5 ns passed the rule; the tied-off run showed it
  was the end of the margin.
- **Let use choose the instructions.** A draft extension has hundreds; a kernel decides
  which come first.

## How I measured, and where the code is

Areas and delays are Yosys and ABC on the sky130 standard cells, typical corner, from the
project's synthesis flow: Mig3Core 420 740 um2 with the packed unit, 414 198 um2 with it
tied off. The blocks are in `rtl/lib/numeric/packed/` (add, saturate, min_max, shift, all
hybrid), the segmented adder in `rtl/lib/part/segmented_kogge_stone_adder.sv`, with their
tests in `test/numeric/packed/` (8-bit lanes exhaustive, every pair of bytes); the packed
unit is `rtl/design/mig3/mig3_packed.sv`, the core's tests `test/design/mig3/pk_*.S`. The
decisions, with the options that lost, are in the knowledge base:
`kb/rtl/design/mig3/p_profile.yaml`, `packed_unit.yaml`, and
`kb/rtl/lib/numeric/packed/design.yaml`, `saturate.yaml`, `min_max.yaml`, `shift.yaml`.
