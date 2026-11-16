# Squeezing out the zeros: stream compaction in log2(N) mux stages

*November 2026. Igor Lesik. Code: [dark-circuit](../README.md), an open library of hardware
blocks and the small RISC-V cores built from them.*

A row of flags, mostly zeros, and the wish for a short list of where the ones are: GPUs
call it stream compaction, particle-physics detectors zero suppression. In a quantum
error-correction decoder it is the step after the detection events: a distance-7 round has
24 of them, nearly all 0, and the decoder wants "defects at 3 and 17". This note is the
block I built for it, StreamCompact, and the small trick that makes it fast: every element
slides down by its own amount, and no two ever meet.

At the size of that round the parallel version is 13 627 um2 and 4.2 ns on SkyWater's
130 nm cells. The obvious loop, synthesized as written, is 32 265 um2 and 12.0 ns.

## 1. The block

```
position:  0 1 2 3 4 5 6 7
flags:     0 1 0 0 1 1 0 1
list:      1, 4, 5, 7      count 4
```

To make it generic, every element carries data, not only its position: element k is
present when valid[k] is 1 and brings data[k]. Positions are just data[k] = k; other data
make it a packer of requests or packets that are present. Out come MAX slots, the present
elements in order, a count, and an overflow flag when there were more than MAX; empty slots
read 0, so a caller needs no guard.

## 2. Count what is below you

Look at any present element and count the absent ones below it, its **gap**:

```
position:      0 1 2 3 4 5 6 7
valid:         0 1 0 0 1 1 0 1
gap:           - 1 - - 3 3 - 4
```

Moving every present element down by its gap puts them at 0, 1, 2, 3, in order. Every
element can work out its gap at the same time, independently: the gaps are a prefix count
of the absent elements, the same structure as the carries of a parallel-prefix adder. In
the library it became a block of its own, PrefixCount (for every bit, the ones below it,
and the total): log2(N) levels, each adding to every count the count 2^l below it, the
adders only as wide as their counts can get, a single bit at the first level.

## 3. Slide by your own amount, one stage per bit

A barrel shifter moves everything by one amount, in stages: by 1, by 2, by 4. Here every
element moves by its own amount, so it carries its gap with it, and stage s moves an
element down by 2^s when bit s of its gap is 1. For the gaps 1, 3, 3, 4 above:

```
slot:      0 1 2 3 4 5 6 7
start:     . 1 . . 4 5 . 7
by 1:      1 . . 4 5 . . 7    gaps 1, 3, 3
by 2:      1 4 5 . . . . 7    gaps 3, 3
by 4:      1 4 5 7 . . . .    gap 4
```

The fact that makes it cheap: **two elements never land in the same lane**, and none passes
another, as long as the small moves come first. Neighbouring gaps grow by the absent
elements between them, which is exactly how far apart the two elements started; after the
moves of the low bits, their distance has shrunk by at most that growth, modulo the
stride, so they stay at least one lane apart. So in every lane of every stage at most one
of two things happens, an element stays or one arrives from 2^s above, and the mux needs no
priority logic:

```systemverilog
// lane j, stage s
keep = v[j]   & !gap_bit[j];
take = v[j+S] &  gap_bit[j+S];
v_next[j] = keep | take;
p_next[j] = take ? p[j+S] : p[j];
```

The rest falls out of the structure. The count is N minus PrefixCount's total of the absent
elements, so the same network gives it. Overflow is an OR of the lanes from MAX up: after
compaction, a lane at MAX or above is occupied exactly when there were more than MAX.

## 4. The numbers

Synthesized with Yosys and ABC on the sky130 cells, the struct version (made of library
blocks and gates) against the behave version (a loop that appends every present element):

- **24 elements, 8 slots, 5-bit data** (a distance-7 round): struct 13 627 um2 and 4.2 ns,
  behave 32 265 um2 and 12.0 ns. The loop maps as written: a chain of 24 decisions, each
  waiting for the count before it.
- **40 elements, 16 slots, 6-bit data** (distance 9): struct 35 492 um2 and 4.9 ns.

The network grows as N log2(N) muxes; the alternative where every slot searches all
elements for the one with its rank grows as N times the slots. I did not build that one, so
it stays a reasoned choice, not a measured one.

## 5. Testing it, and an expensive simulator

Both versions run against one testbench. Up to 12 elements every pattern of flags is
checked; wider ones get the edges (none, all, exactly MAX, MAX + 1) and random patterns of
three densities. The model works differently from both versions: it counts the present
elements, then places them from the top one down. Twelve mutants, small deliberate breakages
of PrefixCount and StreamCompact, are all caught.

The surprise was the event-driven simulator, Icarus: the widest struct configurations took
seconds just to elaborate, before simulating anything, because a gate-level network of a
few thousand instances is large for it. Those configurations run on Verilator only; Icarus
keeps the small widths, where every generate branch is still exercised, and finishes in
about a second.

## 6. What I take from it

- **Turn a search into a count.** "Which element goes to slot j" is a search; "how far does
  each element move" is a prefix count every element can do at once.
- **Order the stages to avoid collisions.** Small moves first, and the muxes need no
  priority.
- **Let the generic version fall out.** Data instead of positions cost nothing and made a
  QEC block a general packer.

## Where the code is

The blocks are `rtl/lib/block/stream_compact/` and `rtl/lib/block/prefix_count/`, behave and
struct versions, with their tests in `test/block/`. The decisions, with the options that
lost, are in `kb/rtl/lib/block/stream_compact/design.yaml` and
`kb/rtl/lib/block/prefix_count/design.yaml`.
