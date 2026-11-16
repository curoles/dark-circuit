# Union-find as a hardware block: a payload it never reads, a mutant that survives

*November 2026. Igor Lesik. Code: [dark-circuit](../README.md), an open library of hardware
blocks and the small RISC-V cores built from them.*

Union-find keeps items in groups that only ever merge, and answers "are these two in the
same group?" in a handful of steps. It is the heart of the Union-Find decoder for quantum
error correction, where clusters of detection events grow and merge, and of older jobs:
labeling connected regions in an image, Kruskal's spanning tree, merging nets. This note is
DisjointSet, the library's union-find block: how it keeps per-group data without knowing
what the data means, a mutant the test can not catch and why that is fine, and how writing
the gate-level version made the behavioral one 30 % faster.

## 1. Union-find in one picture

Every item points to a parent in its group; a root points to itself and names the group.
Two items are in one group when they reach the same root.

```
item:     0  1  2  3  4  5
parent:   0  0  1  3  3  5
groups:   {0,1,2} root 0   {3,4} root 3   {5}

find(2):      2 -> 1 -> 0, root 0
union(2, 4):  roots 0 and 3; parent[3] = 0
```

Two classic tricks keep the trees short:

- **Union by rank:** the root of the lower tree goes under the other, so a tree is at most
  log2(N) high whatever the order of unions.
- **Path halving:** while find walks up, every item it passes is pointed at its
  grandparent, so the next walk is shorter. In hardware it fits the same walk: the block
  reads the parent and the grandparent in one clock and climbs two levels.

The block takes one operation at a time on a valid/ready channel (find, union, set a
group's data, clear everything in one clock) and answers on another. Parents, ranks and
data live in flip-flops for now, a few hundred items, the size of a QEC decoder's graph.

## 2. A payload the block never reads

A decoder keeps data per cluster: its size, whether it holds an odd number of events,
whether it touches the boundary. An image labeler keeps a bounding box. My first thought
was a few fixed fields; the better answer was to let the user bring a type:

```systemverilog
typedef struct packed {
    logic [7:0] size;
    logic       odd;
    logic       boundary;
} cluster_t;

DisjointSetT #(.N(64), .T(cluster_t))
    u_clusters(...);
```

The block stores a T per group and never looks inside. One thing it can not do is merge two
payloads when two groups become one, because the rule depends on the meaning: a size adds,
an odd count XORs (odd plus odd is even, which an OR would get wrong), a boundary flag ORs.
So in the clock a union links, the block shows both groups' payloads, and the user's
combinational logic hands back the merged one:

```systemverilog
assign merge = {merge_a.size + merge_b.size,
                merge_a.odd ^ merge_b.odd,
                merge_a.boundary | merge_b.boundary};
```

## 3. Testing against a different algorithm

The testbench's model has no trees at all: every item carries a group label, and a union
relabels a whole group. Random unions, finds, sets and clears come from a source and the
answers go to a sink, both stalling at random, on 2, 5, 16 and 64 items. Every answer is
checked:

- **the payload** of the item's group, merged with the same rule as the user's;
- **the root,** which must stay the group's root until a union, and then be one of the two
  old roots;
- **the latency:** every answer within 2 log2(N) + 6 clocks of its request.

## 4. The mutant that survives on purpose

The project tests its tests with mutants, small deliberate bugs that must make a test
fail. Thirteen of DisjointSet's fourteen do: a link that forgets to link, a find that stops
at the parent, a clear that clears nothing, an answer dropped before it is taken. The
fourteenth removes path halving, and the test passes.

That is correct, not a gap. Path halving changes only how fast later finds are, never an
answer, and union by rank alone keeps every tree within log2(N), inside the latency bound
the test checks. The mutant stays in the list, marked "survives", with that reason written
next to it. A test proves what it checks; the record says what it does not.

## 5. The gate-level version as a design review

The library writes most blocks twice, a behavioral version and one made of blocks and
gates, and the second is meant as a review of the first. It earned its keep here. The
behavioral version broke the project's own rule for state machines: it updated the state
in one big clocked process together with the tables. Restructured as the gate-level
version would be built (named events of the clock, one write port per table, the state
machine on its own), it also lost a register: the answer's payload is read from the table
at the answer's root, which nothing writes while the answer waits.

Synthesized on SkyWater's 130 nm cells with a 10-bit payload:

- **16 items:** behavioral 6.7 ns before, 4.0 ns after; gate-level 3.9 ns. Areas between
  17 607 and 18 827 um2.
- **64 items:** behavioral 8.5 ns before, 5.9 ns after; gate-level 5.4 ns, 74 039 um2.

The longest path is the price of climbing two levels a clock: the parent read, then the
grandparent read through a second 64-way multiplexer.

Two bugs surfaced on the way, both worth knowing: the testbench released reset exactly at
a clock edge, a race that one simulator resolved one way and the other the other way; and
the block read the reset twice in one branch, legal but fragile. Reset and clear are now
separate branches, and the testbench releases reset a little after the edge.

## 6. What I take from it

- **Let the user own what only the user understands.** A type parameter for the data and a
  merge function for the rule kept the block generic and the decoder's XOR correct.
- **A surviving mutant can be the right answer,** if the reason is written down.
- **Write it twice.** The gate-level version found a structure the behavioral one should
  have had, and both got faster.

## Where the code is

The block is `rtl/lib/block/disjoint_set/` (behave and struct versions, the typed wrapper
DisjointSetT, the operations in DisjointSetPkg), the test `test/block/disjoint_set/`. The
decisions and measurements are in `kb/rtl/lib/block/disjoint_set/design.yaml`, the
mutants with the survivor's reason in `kb/test/block/disjoint_set/mutants.yaml`.
