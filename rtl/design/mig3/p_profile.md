# Mig3 and the P extension (Packed SIMD): the profile

What of RISC-V's P extension Mig3 implements, from which version, in what order, and under
which rules. Decisions here come before any RTL; the knowledge base records them as they are
made (this profile: `kb/rtl/design/mig3/p_profile.yaml`; the chunks' records beside it).

## Why

There is no single must-have use (the user's goals, 2026-11-10):

- **Mig3 as IP with packed SIMD.** What counts is the standard P, followed closely, not a
  vendor extension.
- **Numeric and AI library blocks before Mig6.** The hardware inside P is what a vector lane
  needs: an adder whose carry breaks at lane boundaries, saturation, lane compare and
  min/max, a lane-partitioned multiplier, an int8 dot-product tree. They become hybrid
  library blocks, reused by Mig4/5 (RV64: 8 x 8-bit lanes) and by Mig6's vector and matrix
  units.
- **Light work beside an AI engine.** Mig6's matrix unit may hand quantize/dequantize,
  element-wise int8/int16 work and reductions to Mig3-style cores.

## Version

- **The spec:** RISC-V Packed SIMD "P" Extension, version 0.6 (2026-09-29), the
  Development Milestone, in internal review since 2026-10-23
  (github.com/riscv/riscv-p-spec, `P-ext-proposal.adoc`). Still a draft: encodings may
  change before ratification.
- **The encodings:** riscv-opcodes `extensions/unratified/rv_p` and `rv32_p` at the
  project's pinned commit f24ac23 (its table says v0.20). Compared mechanically with the
  v0.6 document: 542 of the 546 instructions in both have the same encoding; the 4 others
  are scalar RV32/RV64 forms (`rev`, `sati`, `srari`, `usati`), outside the slices below.
  The v0.6 document's 60 new scalar instructions (`aadd`, `mul.h00`, `macc.h00`, `mseq`,
  ...) are not in riscv-opcodes yet, and not used here.
- **The toolchain:** clang-23 knows P as experimental version 0.21
  (`-menable-experimental-extensions`), with the intrinsics of `P-ext-intrinsics.adoc` in
  `riscv_packed_simd.h`: add and subtract (wrapping, saturating, averaging), min/max,
  compares, absolute values and differences, reductions, merge; no multiplies, dot
  products or shifts (inline assembly for those).
- **Re-syncing** to a newer draft or the ratified version is regenerating RiscvInstrPkg
  (`tools/riscv_opcodes.sh`, its pinned commit moved) and following the decode tests: they
  are assembled by clang and decoded by the RTL from riscv-opcodes, so the two sources
  must agree; a renamed instruction stops the build, an instruction on a new opcode
  fails the interlock's assertion (`a_hz_covers_uses`). A newer clang: P's version is
  read from clang (`-print-supported-extensions`), not written in `cmake/riscv.cmake`, so
  the P tests are not skipped silently (a chunk after 2g); the kernel's inline assembly
  wrappers take the names of `P-ext-intrinsics.adoc`, dropped when clang has them.

## Prerequisites

- **Zba** (`sh1add`, `sh2add`, `sh3add`): P depends on Zmmul, Zba and Zbb. Mig3 has M and
  all of RV32 Zbb, not Zba.
- **vxsat:** the saturating instructions set the vector extension's saturation flag. Mig3Csr
  gets `vxsat` (one bit, read and written by CSR instructions), set when a saturating
  instruction completes, as `fflags` is by the FPU. `mstatus.VS` is not required by P and
  is not added.

## The slices and their chunks

Instruction names and encodings are the spec's; `.b` is four 8-bit lanes, `.h` two 16-bit
lanes in Mig3's 32-bit registers. No register-pair (64-bit result) forms: they read and
write two registers and come, if ever, after Mig4's RV64 makes them unnecessary.

Chunks are small (the user: small enough to review, each with its timing measured): a
library block or a few instructions at a time, every chunk passing the suite and the
timing rule below. A chunk with a new library block comes in two: the block with its own
test, then Mig3 (2c-1 PackedSaturate, 2c-2 the saturating instructions).

**The order follows the int8 kernel** (below; revised 2026-11-11 after 2c): what an int8
layer needs comes first, the rest waits until something asks for it:

1. Prerequisites: 1a, 1b (done).
2. Packed ALU: 2a, 2b, 2c (done); 2g `pmin`, `pmax` (activation and clamping) next,
   then P's version read from clang (below, Re-syncing).
3. Shifts by an immediate and by a register: 3a, 3b.
4. Multiplies and dot products: their library blocks first (4a the lane-partitioned
   multiplier, 4d's dot-product tree; the same in any ISA), their Mig3 instructions after
   a look at the draft's activity (the group most likely to change); the kernel comes
   with the dot products (4d).
5. Requantization: 3c's rounding and saturating shifts with the multiply-high forms the
   kernel's requantization uses (chosen when it is written; scalar `mulhr`, `mulqr`,
   `srari`, `sati` are candidates, and riscv-opcodes' RV32 `sati`, `srari` differ from
   the v0.6 document: checked then).
6. Data movement the kernel needs: `psext.h.b` (bytes to halfwords), `ppaire`, `ppairo`
   (packing).

**Deferred** (one more select input each, cheap; they come back when a kernel uses them):

- 2d averaging (`paadd`, `paaddu`, `pasub`, `pasubu`): codecs, image blending and audio
  mixing average, with rounding (x86 `pavgb`, Arm `urhadd`); P's forms truncate, and no
  int8 layer averages pairs.
- 2e absolute difference (`pabd`, `pabdu`): its use is the sum of absolute differences of
  motion search and template matching, which P has as `pabdsumu.b`, `pabdsumau.b`.
- 2f compares (`pmseq`, `pmslt`, `pmsltu`): masks for a select (`merge`); clamping is
  `pmin`, `pmax`.

1. **Prerequisites.**
   - 1a: Zba (`sh1add`, `sh2add`, `sh3add`) in the ALU.
   - 1b: the `vxsat` CSR.
2. **Packed ALU, one cycle at the ALU's width** (each instruction `.b` and `.h`).
   - 2a: the lane-cut adder block (library), timed on its own.
   - 2b: `padd`, `psub` (Mig3's first P instructions: decode, the packed unit in EX).
   - 2c: saturating `psadd`, `psaddu`, `pssub`, `pssubu` (they set `vxsat`).
   - 2d: averaging `paadd`, `paaddu`, `pasub`, `pasubu`.
   - 2e: absolute difference `pabd`, `pabdu`.
   - 2f: compare `pmseq`, `pmslt`, `pmsltu`.
   - 2g: `pmin`, `pminu`, `pmax`, `pmaxu`.
3. **Packed shifts.**
   - 3a: by an immediate, `pslli`, `psrli`, `psrai`.
   - 3b: by a register, `psll`, `psrl`, `psra` (`.bs`, `.hs`).
   - 3c: rounding `psrari.h`, saturating `psati.h`, `pusati.h`.
4. **Packed multiplies and dot products,** through a result register like Mig3Fpu.
   - 4a: the lane-partitioned multiplier block (library), timed; shared with Int32Mul or
     not, by measurement.
   - 4b: 8 x 8 to 16-bit lanes, `pmul.h.b00`, `pmul.h.b11` and their unsigned and mixed
     forms.
   - 4c: 16 x 16 high halves, `pmulh.h`, `pmulhu.h`, `pmulhr.h`, Q15 `pmulq.h`.
   - 4d: the dot-product tree (library) and `pm4add.b` (four int8 products summed into 32
     bits), `pm2add.h` (two int16), with their unsigned and mixed-sign forms.
   - 4e: the accumulating forms `pm4adda.b`, `pm2adda.h` and the rest: they read rd as a
     third source, through the read port borrowed in EX (kb `rtl/design/mig3/rs3_read`).

Later, if wanted: reductions (`predsum`), sums of absolute differences (`pabdsumu.b`), the
cross forms (`pas.hx`, ...), `merge`, `mvm`, packing.

## The int8 kernel

The yardstick of the line: one C program on Mig3, a fully connected int8 layer as
TensorFlow Lite Micro and CMSIS-NN run it, a matrix of 8-bit weights times a vector of
8-bit inputs:

    acc[n] = bias[n] + sum over k of x[k] * w[n][k]       (32 bits)
    y[n]   = clamp(zero_point + requantize(acc[n]))       (8 bits, four to a word)

requantize is a Q31 multiply with rounding and a rounding shift right; clamp keeps the
activation's range (ReLU: no negatives). Two versions in the program, plain C (the
reference) and P (the intrinsics, inline assembly where they stop), run side by side on
the same random weights and inputs: every output equal is exit 0 (as `fp_diff`), and the
cycles of both are printed. It enters with the dot products (4d: four multiply-adds per
instruction), each later slice moves another step to P, and the cycle counts show what
each slice buys. What it would use decides what comes after the order above.

## Library blocks first

Each slice begins with its blocks in `rtl/lib`, hybrid family, tested on their own:

- **A lane-cut adder:** 32 bits with the carry cut at 8 or 16 by the lane mode; the
  saturating and averaging results from the lane carries; lane compare from the same adder.
  8-bit lanes are tested exhaustively (every pair), 16-bit lanes by random and edge values.
- **Packed shifts:** the BarrelShifter with lane masks, or a shifter per lane width.
- **A lane-partitioned multiplier** (4 x 8 x 8, 2 x 16 x 16) and **an int8/int16
  dot-product tree** with an accumulate input.

Then Mig3: decode by riscv-opcodes names (RiscvInstrPkg), a control struct per unit, EX.

## Testing in Mig3

- **The decode test,** as for Zfinx: every chosen instruction, assembled, with its controls
  against a model.
- **Assembly with expected registers,** per slice: each instruction with lanes that saturate,
  overflow, round, and vxsat set and read back.
- **Differential C, as fp_diff:** the int8 kernel (above), P against plain C, every output
  equal.

## The timing rule

Mig3's clock stays: every P chunk's sky130 run must show Mig3's longest path at 5.5 ns within
ABC's spread, with no P logic on top. If it moves, the chunk is not done.

- **One-cycle operations** (slices 2 and 3) sit in EX if the result select allows: the
  lane-cut adder is the ALU's adder with carry gating; saturation, compare and min/max add
  one select. The slow input goes into the select last (kb
  `rtl/design/mig2/late_input_last_mux`).
- **Multiplies and dot products** go through a result register: one bubble each, no FP or
  multiply logic on the forwarding path (as kb `rtl/design/mig3/fpu`).
- **Fallback:** if even the one-cycle operations crowd the select, they go through the
  result register too. The clock stays; four lanes per instruction still win.
- **Early check:** the lane-cut adder is synthesized on its own in its library chunk, against
  a plain 32-bit adder, before it goes near Mig3.
- **Area:** a multiplier of its own costs about as much as Int32Mul (about 47 000 um2, 14 %
  of Mig3); sharing Int32Mul's array adds selects inside it. Decided by measurement in
  slice 4. A struct block in the middle of a critical chain stops synthesis optimizing
  across it (Fp32FromInt: 5.2 ns struct, 4.8 behave, 2026-11-11); where that sets the clock,
  restructure, or record a behave exception.

## Not in this profile

- Register-pair forms (64-bit results on RV32).
- Misaligned loads and stores: P recommends efficient ones; Mig3 keeps trapping on them.
- `mstatus.VS` and the `*stateen` VXSAT bit (Mig3 has neither stateen nor V).
- Zkt (data-independent latency): Mig3's P units have fixed latency, but Zkt is not
  claimed.
