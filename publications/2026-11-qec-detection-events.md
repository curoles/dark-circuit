# What a QEC decoder actually sees: detection events for hardware designers

*November 2026. Igor Lesik. Code: [dark-circuit](../README.md), an open library of hardware
blocks and the small RISC-V cores built from them.*

Quantum error correction is usually explained from the physics up. This note goes the other
way: from the bits a decoder chip receives every microsecond, up. I took a short detour into
QEC to build the front end of a surface-code decoder as library blocks: the code's layout,
the detection events, and the parity checks of the final round. No decoder yet; the
detour stopped there, on purpose. But the front end is where most of the ideas a hardware
designer needs are, and none of it needs quantum mechanics beyond one paragraph.

For the physics, Joschka Roffe's "Quantum Error Correction: An Introductory Guide"
(Contemporary Physics, 2019, arXiv:1907.11157) is the place to start; the terms below are
his.

## 1. Parity questions instead of reading the data

A data qubit can not be read while it computes: measuring it destroys the state. So a
quantum computer never looks at its data qubits. It only asks parity questions about small
groups of neighbours, "is the number of flipped qubits among these four even or odd?", each
answered through a helper qubit that learns the parity and nothing else. Each question is a
**stabilizer**. Two kinds exist: Z-type stabilizers notice bit flips (X errors), X-type
stabilizers notice phase flips (Z errors).

In the rotated surface code of distance d, d x d data qubits sit on a grid and the
stabilizers sit between them, each touching four qubits inside and two on the edge. For
d = 3, nine data qubits and four stabilizers of each kind:

```
  plaquette        0     1     2     3
  row 0                        X
  data row 0          o     o     o
  row 1            Z     X     Z
  data row 1          o     o     o
  row 2                  Z     X     Z
  data row 2          o     o     o
  row 3                  X
```

In the library this is a package of functions of d, QecPkg: which plaquettes hold which
kind of stabilizer, and which data qubits a stabilizer touches. Blocks and testbenches
compute their tables from it for any odd d.

## 2. Testing a layout by what makes it a code

A table of who touches whom is easy to get subtly wrong, and comparing it with another
table only moves the problem. So QecPkg's test checks the properties that make the layout a
working code, for d = 3, 5, 7 and 9:

- **The checks commute.** Every X-type and every Z-type stabilizer share an even number of
  data qubits, 0 or 2. Otherwise they could not all be measured together.
- **Every qubit is watched.** Each data qubit is touched by 1 or 2 stabilizers of each
  kind, so every single error is seen.
- **The weights are right.** Four qubits inside, two on the edge.
- **The logical operator is invisible.** X errors on a whole column, top to bottom, touch
  every Z-type stabilizer twice or not at all: no stabilizer notices. That is how the
  stored value itself changes, and it takes d errors, so the distance is d.

A layout that passes these is a code; one that fails them is broken in a way a table
comparison might never show. One of the test's mutants turns the layout by 90 degrees,
Z-type stabilizers at the top instead of the sides. That is still a valid code, and only
the logical check notices that the column is no longer invisible.

## 3. Detection events: did the answer change?

About every microsecond all the questions are asked again; one round gives one bit per
stabilizer, the syndrome. A decoder does not decode the syndrome, for two reasons:

- **An error stays.** A qubit that flips between rounds 4 and 5 makes its stabilizers
  answer 1 in round 5 and in every round after it.
- **The answers can be wrong.** The helper qubit is noisy too; now and then one answer of
  one round comes out flipped.

So the first block after the readout asks, per stabilizer, whether the answer changed since
the last round: this round XOR the last one, a **detection event**.

```
round:           1 2 3 4 5 6 7
data error:      0 0 0 1 1 1 1
events:          0 0 0 1 0 0 0

wrong answer:    0 0 0 1 0 0 0
events:          0 0 0 1 1 0 0
```

Every fault leaves two ends. A data error inside the grid gives two events side by side in
one round (at the edge one; the other end is the boundary); a wrong measurement gives two
events at one stabilizer in consecutive rounds. A decoder sees dots in space and time and
pairs them up with the most likely faults, which is why the decoding graph is
three-dimensional.

Two rounds are special:

- **The first** has no round before it. An experiment that starts with every qubit in
  state 0 knows the Z-type answers (0), so they are compared with 0; the X-type answers are
  random the first time and give no event.
- **The last:** the data qubits are finally read directly, and the stabilizers' parities
  are computed from those bits. That round goes in like any other.

The block, DetectionEvents, is small: a register for the last round, an XOR, and two masks
(first round, no round). N flip-flops and about three gates a bit. Its test runs a memory
experiment through QecPkg: random data errors and wrong measurements on distances 3 and 5,
and every data error must give events exactly at its one or two Z-type stabilizers, every
wrong measurement exactly two events at one stabilizer.

## 4. The final round: a parity check is a matrix

The parities of the last round are a parity-check matrix times a vector over GF(2), bits
where AND multiplies and XOR adds: row r of H marks the data qubits stabilizer r touches,
and the syndrome is the parity of the measured bits under each row. The same operation is
the syndrome of every linear code: Hamming and SECDED memory ECC, a CRC of a whole word in
one clock, LDPC. So the library got one generic block, ParityCheck:

```systemverilog
// syndrome[r] = ^(h[r] & in)
ParityCheck #(.ROWS(12), .COLS(25))
    u_final(.h(H), .in, .syndrome);
```

The matrix is an input, not a parameter. Tied to constants, synthesis folds the AND gates
away and keeps only the XOR trees of the chosen bits; driven by registers, the code is
programmable. Measured on SkyWater's 130 nm cells, the 12 x 25 matrix of a distance-5 code:

- **Tied to QecPkg's table:** 255 um2, 51 cells, 0.5 ns. That is the 28 XOR gates of the
  checks: eight checks of four bits (three gates each) and four of two (one each).
- **Programmable:** 4 139 um2, 589 cells, 0.9 ns, sixteen times the area.

One surprise on the way: tying the distance-9 matrix (40 x 81) did not finish. The table is
computed by a constant function, and the synthesis tool evaluates it in an interpreter,
3 240 calls each walking the whole layout. A block that builds its wiring from QecPkg will
need a one-pass table function first.

## 5. What I take from it

- **The front end is ordinary hardware.** A register and an XOR per stabilizer, a parity
  tree per check. The hard part of a QEC decoder, pairing the events under a latency budget
  of about a microsecond a round, comes after.
- **Test a structure by its defining properties.** Commuting checks, watched qubits and an
  invisible logical operator say "this is a code" more strongly than any table.
- **Generic blocks fall out of a niche.** Parity checks, and the stream compaction and
  union-find of the next notes, serve QEC and many other things.

## How I measured, and where the code is

Areas and delays are Yosys and ABC on the sky130 standard cells, typical corner, from the
project's synthesis flow. The package is `rtl/lib/qec/qec_pkg.sv`, the block
`rtl/lib/qec/detection_events/`, the parity check `rtl/lib/block/parity_check/`, with their
tests in `test/qec/` and `test/block/parity_check/`. The decisions, with the options that
lost, are in `kb/rtl/lib/qec/surface_code.yaml`,
`kb/rtl/lib/qec/detection_events/design.yaml` and
`kb/rtl/lib/block/parity_check/design.yaml`.
