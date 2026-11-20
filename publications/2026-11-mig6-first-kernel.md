# 3.7 times faster with four cores: the first kernel on my RISC-V mesh

*November 2026. Igor Lesik. Code: [dark-circuit](../README.md), an open library of hardware
blocks and the small RISC-V cores built from them.*

My earlier note ran an int8 fully connected layer (TFLite Micro's, 64 inputs, 16 outputs)
on one RISC-V core, Mig3: 9 220 cycles in plain C, 2 560 with one packed-SIMD instruction.
This note runs the same layer on Mig6, a prototype of four Mig3 cores on a network on chip,
toward a small AI chip. Each core computes 4 of the 16 outputs, every output is compared
with the one-core result bit for bit, and the layer takes 2 527 cycles instead of 9 314:
3.7 times faster.

Four cores giving 3.7 is no surprise; splitting a layer by outputs is about as parallel as
work gets. What is worth telling is the machine that does it with so little: no cache
coherence, no messages between cores, a barrier made of one atomic instruction. And what the
number does not show yet.

## 1. Mig6 in one picture

```
              +-----------+
              |  shared   |  network interface,
              |  memory   |  atomics, RAM
              +-----------+
                    |
  +---------+  +---------+
  | PE 2    |--| PE 3    |
  +---------+  +---------+
       |            |
  +---------+  +---------+
  | PE 0    |--| PE 1    |
  +---------+  +---------+

  every line: two networks, requests and answers
```

- **A PE** (processing element) is a Mig3 core, its caches and a local memory of 64 KiB
  that only it uses, for code and private data. Its network interface is its only door to
  the others.
- **The shared memory** sits at the edge of the 2 x 2 mesh, on the north link of PE 3, so
  all four nodes are PEs. A request from PE 0 passes three routers to get there.
- **Only memory requests travel:** loads, stores, atomics, and their answers. No custom
  messages between cores: they look simple at first, then every new kind needs a case in
  every network interface and brings new ways to deadlock. A core, a DMA engine and a
  future matrix engine all speak loads and stores.
- **Two networks,** one for requests, one for answers (the library's NocMesh, twice). If
  requests fill theirs, answers still drain on the other, so the two classes can never
  block each other. Wires on a chip are cheap; this is how AMBA CHI, OpenPiton and Tilera
  do it too.

## 2. One copy of everything

Coherence is a problem of copies: it appears only when two places hold the same data and
one of them writes it. Mig6 keeps one copy of everything:

- **Local memory is private.** The core caches it, and nobody else ever looks.
- **Shared memory is never cached.** Every load and store to it crosses the network; the
  only copy is in the RAM.
- **Synchronization by atomics at the memory.** An `amoadd.w` travels to the shared memory
  and is done there, next to the RAM, by a block in front of it (my note on atomics next to
  the memory). The counter lives in one place only.

The price is a round trip for every shared access, so a program touches shared memory
deliberately and rarely. The layer does: two stores and a barrier a round.

## 3. One binary, four parts

Every PE runs the same program (SPMD). A PE learns which part is its own from `mhartid`,
the RISC-V hart ID, which the grid gives each PE as a parameter. The local memory has the
same addresses in every PE, so one binary is loaded into all four.

```c
const uint32_t hart  = csr::mhartid::read();
const int      first = 4 * hart;  // my rows

make_data();                      // x, w, bias
barrier(count, ++k);
int8_fc_ref_rows(x, w, bias, &q, y, first, 4);
uint32_t out = 0;                 // 4 outputs
for (int i = 0; i < 4; i++)
    out |= (uint8_t)y[first + i] << (8 * i);
shared[hart] = out;               // one store
barrier(count, ++k);
```

- **The data is made in place.** Every hart runs the same generator (Mig3's test's), so
  each has the whole input and all the weights in its local memory before the layer
  starts. Wasteful (a PE needs 4 of the 16 rows), and on purpose for now: this chunk
  measures the split, not the transport.
- **Four outputs are one word,** so a PE's results cost one store over the network.
- **Hart 0 is also the referee.** Before the first barrier it runs the whole layer alone:
  that gives the expected outputs and one PE's cycles. After the second barrier it reads
  the four words, compares all 16 bytes and exits 1 at the first mismatch. The exit code is
  the verdict; nobody greps a log.

## 4. A barrier made of one atomic

```c
bool barrier(volatile uint32_t* count, uint32_t k)
{
    __atomic_fetch_add(count, 1u, __ATOMIC_SEQ_CST);
    uint32_t start = csr::cycle::read();
    while (__atomic_load_n(count, __ATOMIC_ACQUIRE)
           < N_HARTS * k)
        if (csr::cycle::read() - start > WAIT)
            return false;
    return true;
}
```

- **The counter only grows.** Barrier k ends when the count reaches 4 k. The textbook
  barrier resets its counter to 0, and then a fast hart can arrive at the next barrier
  before a slow one has seen the last; the cure is a "sense" flag that flips each time.
  A counter that never goes back needs neither.
- **The results are in memory before the arrival,** with no acknowledgement of writes: a
  PE's requests all take the same XY path on one virtual channel, so the store arrives
  before the `amoadd` that follows it, and the memory serves them in that order. This is a
  property of the network as it is today (one virtual channel, one destination), written
  down as such in the design notes.
- **A wait has an end.** A barrier that some hart never reaches would hang the simulation
  forever; the cycle counter ends it, and the program exits 2.
- **It costs 50 to 90 cycles.** The `amoadd` and the polling loads cross the network; the
  PE next to the memory arrives first.

## 5. Where the other 0.3 went

Round 1's numbers:

- **One PE, the whole layer:** 9 314 cycles. A quarter of it is 2 329.
- **Each PE, its 4 rows:** 2 433 to 2 438 cycles, about 104 more than a quarter.
- **Four PEs,** from the first barrier to the second as hart 0 sees it: 2 527 cycles. The
  89 above the slowest PE are the store and the barrier.

So 9 314 / 2 527 = 3.69. The barrier's share is the expected one. The 104 cycles were not
what I expected, so I read the code. The inner loops are the same seven instructions per
multiply-add in both functions:

```
loop:  lb    a3, 0(a2)      # x[k]
       lb    a4, 0(a1)      # w[n][k]
       mul   a3, a4, a3
       addi  a2, a2, 1
       add   a0, a3, a0     # acc +=
       addi  a1, a1, 1
       bne   a2, s7, loop
```

The difference is around them. The whole-layer function lives in the same file as the
requantization, and the compiler inlines it. The rows function lives in a file of its own,
so that Mig3's test keeps its code byte for byte, and there the requantization is a real
call, four times, plus nine registers saved and restored. Link-time optimization or an
inline header would take the 4 % back; I left it, since this layer is plain C only until
the engine arrives.

The unfairness of the network does not show here either. Router (1, 1) takes its inputs in
turn, so PEs 2 and 3 get a third of the shared memory each and PEs 0 and 1 a sixth; with
a store and two barriers a round, nobody waits for the memory.

## 6. Four cores against one instruction

The same layer on one Mig3 with P's `pm4adda.b` (four byte products added to a 32-bit sum,
one instruction) takes 2 560 cycles. Four Mig6 PEs in plain C take 2 527. Four cores to
match one instruction: P is by far the cheaper way to that speed (11 % more area on one
core, measured on Mig3, against three more cores).

Yet Mig6's cores have no P. On RV32, P's 64-bit forms keep a value in a register pair, up
to four registers read and two written by one instruction, against the core's two read
ports and one write port; and clang uses those forms for any 64-bit arithmetic once P is
on. Making that work means a bigger register file and a tighter clock, or pair
instructions over several cycles. And each PE is meant to get a small int8 matrix engine,
which does the dot products far better than P could. So P stays in Mig3, returns on a
64-bit core where there are no register pairs, and Mig6 runs the layer in plain C until
the engine comes.

## 7. What 3.7 hides

All the data was already in each PE's local memory. The network carried a barrier and 16
bytes of results per round, nothing else. A real layer starts with its weights somewhere
shared, and getting each PE its part is the real work of a multi-core chip.

That is the next step: a DMA engine in each PE fetching its rows from the shared memory
over the same network, the same requests a core sends. Then the comparison that matters:
the same layer, data local against data fetched, and what the network and the memory make
of four PEs asking at once.

## The code

- **The program:** `test/design/mig6/fc_layer.cpp`; the kernel in
  `sw/riscv/kernels/int8_fc/` (the reference, its rows, the requantization).
- **The machine:** `rtl/design/mig6/` (Mig6, Mig6Pe, the network interfaces, the memory
  map) and its README, the working plan.
- **The decisions:** `kb/test/design/mig6/fc_layer.yaml` (the test),
  `kb/rtl/design/mig6/no_p.yaml` (no P), `kb/rtl/design/mig6/far_lr_sc.yaml` (LR/SC at
  the shared memory).
- **Earlier notes:** [the int8 kernel on one core](2026-11-int8-kernel.md),
  [atomics next to the memory](2026-11-atomics-next-to-memory.md),
  [exclusive access on shared memory](2026-11-exclusive-access-lr-sc.md).
