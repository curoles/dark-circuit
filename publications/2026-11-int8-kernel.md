# 3.6 times faster with one instruction: an int8 layer on my RISC-V core

*November 2026. Igor Lesik. Code: [dark-circuit](../README.md), an open library of hardware
blocks and the small RISC-V cores built from them.*

Mig3, my 5-stage in-order RISC-V core, runs 63 instructions of RISC-V's draft packed SIMD
extension, P. All of them were chosen for one yardstick: an int8 fully connected layer, as
TensorFlow Lite Micro runs it, written twice, in plain C and with P, on the same core and
the same data. The P version takes about 2 560 cycles, the plain one about 9 220: 3.6
times faster, from one instruction in the inner loop.

This note is the kernel, where its cycles go, the trap it fell into first, and why the P
line in Mig3 stopped right after it.

## 1. The layer

A fully connected layer of 8-bit inputs and weights, 64 inputs and 16 outputs:

```
acc[n] = bias[n] + sum x[k] * w[n][k]
y[n]   = clamp(zp + requantize(acc[n]))
```

The products and their sum are 32-bit integers. Requantization brings the sum back to 8
bits: TFLite multiplies it by a Q31 fixed-point multiplier with rounding, shifts it right
with rounding, adds the output's zero point and clamps to the activation's range. It is a
few lines of C with 64-bit arithmetic in them, and it will matter twice in this story.

## 2. Two versions, one judge

The test is a C program on the core, judged by its exit code:

- **Same inputs.** Random inputs, weights and biases, three rounds, each with its own
  quantization; one round has a ReLU (the activation's minimum at the zero point).
- **Same requantization.** Both versions call one requantization function, so their
  outputs must agree bit for bit, and they differ only in the dot products.
- **Cycles from the core.** Each version is timed with `rdcycle`, and the counts are
  printed through semihosting.

## 3. The inner loops

The plain version is the obvious loop:

```c
for (int k = 0; k < 64; k++)
    acc += (int32_t)x[k] * w[n*64 + k];
```

clang turns it into seven instructions per product:

```
lb   s0, 0(t6)
lb   s1, 0(t5)
mul  s0, s1, s0
addi t6, t6, 1
add  t4, s0, t4
addi t5, t5, 1
bne  t6, a7, loop
```

The P version reads four bytes of each operand as one word and uses PM4ADDA.B: the four
byte products added to rd. clang 23 has no intrinsic for it yet, so a small wrapper in
inline assembly takes the name from P's intrinsics document:

```c
for (int k = 0; k < 64 / 4; k++)
    acc = __riscv_pm4adda_i8x4(
              acc, x4[k], w4[k]);
```

The loop has 16 iterations of a known count, and clang unrolls it completely: per output,
32 word loads and 16 PM4ADDA.B, then the call to the requantization. No loop branch is
left inside.

## 4. Where the cycles go

Counting from the code, and checked against the measured totals:

- **Plain C: about 8 cycles per product.** Seven instructions, and the MUL waits one cycle
  for the byte loaded right before it. 1 024 products are about 8 200 cycles; the rest of
  the 9 220 is requantization and the loop around it.
- **P: 4 cycles per PM4ADDA.B,** which is four products. The multiplier has a pipeline
  register and a result register, and an accumulating form reads rd through a borrowed
  read port first, so each one holds EX for 4 cycles: 3 of them bubbles, 768 per round.
  256 of them are 1 024 cycles.
- **P: the loads.** Two word loads per PM4ADDA.B, 512 cycles.
- **P: requantization, now 40 %.** The same roughly thousand cycles as in the plain
  version, for 16 outputs and the calls, now about 40 % of the total.

So two things stand between this kernel and more speed. The multiplier's latency: a unit
that kept the accumulator inside and took a new PM4ADDA.B every cycle would save most of
the 768 bubbles. And the requantization: it was a tenth of the plain version and is now
40 % of the P one, the usual fate of the part nobody sped up.

## 5. The trap

The first build had the requantization in the P file, as plain C. The kernel trapped on an
illegal instruction.

With P on, clang compiles 64-bit arithmetic on RV32 into P's register-pair instructions:
the 32 x 32 to 64 multiply became WMUL, the 64-bit adds ADDD, the shifts NSRLI and WSLAI.
Each reads or writes a 64-bit value held in two registers. Mig3 has none of them, because
they need up to four read ports and two write ports, against Mig3's two and one.

Two changes made the kernel run, and both stayed:

- **P only where it is meant.** Only the P loop's file is compiled with P. The
  requantization, the reference, the driver and the startup code are compiled without it.
- **The binary checked against the decoder.** A second test disassembles the P object and
  compares every instruction with the names in Mig3's decoder. If a newer clang finds
  another use for P, this test fails at build time, not the core at run time.

What clang does with P on its own, in ordinary C, is the subject of an earlier note.

## 6. Why the line stopped here

This kernel was meant to be the first step of more: requantization with P's rounding
multiplies, data-movement instructions, then the rest of the draft. It became the last.

- **Full P on RV32 means register pairs.** Any C compiled with P uses them for 64-bit
  arithmetic, and they do not fit a core with two read ports and one write port.
- **The draft and the compiler still move.** P is version 0.6 in review; clang calls its
  support 0.21, experimental, without multiply intrinsics.
- **P's natural home is a 64-bit core.** On RV64 there are no scalar register pairs, and
  the lanes double.

What stays is the hardware: a lane-cut adder, saturation, lane min/max and shifts, and a
packed multiplier with byte and halfword dot products, all library blocks that already
take 64-bit words. They are what a vector lane is made of.

## 7. What I take from it

- **One kernel is a good yardstick.** It ordered 63 instructions out of hundreds and gave
  a number that means something: cycles for a layer, outputs compared bit for bit.
- **Count the cycles, not just the total.** 3.6 times is the headline; the breakdown says
  where the next factor would come from, and that it is not more instructions.
- **Amdahl arrives fast.** One fast instruction turned the requantization from a tenth of
  the time into 40 % of it.
- **A compiler flag is a promise.** The core has part of P; the build says P only in the
  file that uses that part, and a test checks that the promise holds.

## How I measured, and where the code is

Cycles from `rdcycle` on Mig3 in Verilator, three rounds: plain C 9 214 to 9 322, P 2 558
to 2 565. Ubuntu clang 23.1.6, `-O2`, `-march=rv32im_zba_zbb` for the plain files and
`rv32im_zba_zbb_p0p21` for the P file; the breakdown in section 4 is counted from clang's
assembly output, not measured cycle by cycle. The kernel is
`test/design/mig3/int8_kernel.h`, `int8_kernel.c` (driver), `int8_kernel_ref.c` (reference
and requantization) and `int8_kernel_p.c`; the instruction check is
`tools/check_insns.py`, run as the test `design_mig3_int8_insns`. The decisions are in
`kb/test/design/mig3/int8_kernel.yaml`, and the P subset and why it stopped in
`rtl/design/mig3/p_profile.md`.
