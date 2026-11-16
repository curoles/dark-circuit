# Mig6: Mig3 cores on a network on chip, toward an AI chip

**Status: a prototype, being explored.** This page is the working plan, not a specification:
every choice below is "for now", made to get a first system running and measured, and any of
them may change as we learn. Open questions are listed at the end; decisions that settle get
kb records, as elsewhere in the project.

Mig6 is the AI-chip line of the roadmap: built from Mig3 (not from Mig4 or Mig5), no
operating system, no MMU, physical addresses, RV32. It is not a commercial product: the only
consideration is convenience for developing numeric and AI library blocks and for AI
experiments. It gives a home to library blocks that have none yet: the network on chip
(rtl/lib/block/noc), the far atomics (AtomicUnit), the DMA, the packed multiplier.

## The first target

One workload defines the first milestone: the int8 fully connected layer of the int8 kernel
(test/design/mig3/int8_kernel*, publications/2026-11-int8-kernel.md), 64 inputs and 16
outputs, run on four PEs at once, every output compared with the plain-C reference, the
cycles compared with one Mig3: 9 220 cycles in plain C, 2 560 with P.

## The system, for now

```
              +-----------+     +-----------+
              |  PE (0,0) |-----|  PE (1,0) |
              |  hart 0   |     |  hart 1   |
              +-----------+     +-----------+
                    |                 |
              +-----------+     +-----------+
              |  PE (0,1) |-----|  PE (1,1) |-----> edge link: shared memory
              |  hart 2   |     |  hart 3   |       (network interface, AtomicUnit, RAM)
              +-----------+     +-----------+

  the lines between PEs are the NoC (NocMesh: routers and links), outside the PEs
```

- **A 2 x 2 mesh of PEs** (NocMesh, one slice): enough for a real parallel speedup and real
  network traffic (up to two hops with XY routing), small enough to simulate on a laptop.
  The mesh is parameterized; a larger grid is a parameter.
- **Shared memory on an edge link** of the mesh, outside the grid, so all four nodes are PEs:
  a network interface, AtomicUnit (atomics done next to the memory) and a RAM.

## What travels on the NoC, for now

Only memory requests and their answers: one protocol, the loads, stores and atomics that
cores, DMA engines and future engines all speak. No custom messages between PEs: they look
simple at first and scale badly (more packet kinds, special cases in every network
interface, new ways to deadlock, a programming model that does not carry over).

- **Requests,** from a PE to the shared memory: read, write, atomic, with the address, the
  operation, and the data and strobes of a write.
- **Answers,** from the shared memory back to the PE: the data of a read, the old value of
  an atomic.
- **PEs talk only to the shared memory,** for now. Reading or writing another PE's local
  memory would be the same protocol with another destination (an address window), not a new
  kind of packet; it may come when chained layers pass data from PE to PE.
- **Requests and answers on separate virtual channels** (message classes): if requests fill
  the network, answers still get through and free room, so the two never block each other
  (no protocol deadlock).
- **One virtual channel per class, for now,** so a PE's requests to the shared memory keep
  their order: they take the same XY path on the same channel, and AtomicUnit serves them as
  they arrive. A PE's result stores are in memory before its barrier `amoadd`, without
  acknowledgements of writes.

## A PE: Mig6Pe

```
  Mig6Pe:
    Mig3 core --> address decode --+--> local memory      (only this core uses it)
                                   |
                                   +--> network interface --> router (outside the PE)
                                        (shared memory: uncached)
```

- **One core a PE, for now.** A PE may later get a matrix engine or a second core without
  changing the grid.
- **Local memory:** code and private data, only this core uses it; the core's caches sit in
  front of it as in Mig3.
- **Network interface:** the PE's door to the NoC; requests to the shared memory leave
  through it as packets, answers come back.
- **The same program on every PE** (SPMD): each finds its part from `mhartid`, the RISC-V
  hart ID, a parameter of the PE (Mig3 reads 0 today).

## Memory: why no coherence and no L2 yet

Coherence is a problem of copies: it arises only when two places hold the same data and one
writes it. Mig6 keeps one copy of everything, for now:

- **Local memory is private.** Copies in the core's caches are never seen by another core.
- **Shared memory is never cached.** Every load and store to it goes through the NoC to the
  memory (Mig3's uncached requests); the only copy is there.
- **Synchronization by atomics at the memory:** a barrier is an `amoadd` on a counter in
  shared memory, done by AtomicUnit next to the RAM, the only place the counter lives.

The price: a shared access is a round trip over the network, so programs touch shared memory
deliberately and rarely. An L2 would cache a large slow memory; here the shared memory is a
simulated RAM and the local memories are the fast level, so there is nothing for it to do.
If shared data is ever cached for speed, coherence comes back as a choice: by software with
Zicbom (cbo.clean, cbo.inval, already in Mig3) or a directory protocol (MSI/MESI).

## The address map, for now

- **Local memory** at 0, the same addresses in every PE (one binary for all), as Mig3's
  memory (64 KiB).
- **Shared memory** in an uncached window. A first idea: a part of Mig3's I/O region
  (`0x0C000000`, uncached already) decoded to the network interface, so that Mig3 needs no
  new region; to check with atomics (Mig3's devices take no AMOs, the shared memory must).
- **Other PEs' local memories** over the NoC: not needed by the first target; later.

## The layer on four PEs

- **Split by outputs:** each PE computes 4 of the 16 outputs, from its 4 rows of the weights
  and the whole input, with the P kernel of the article.
- **Data, for now:** the testbench loads every PE's local memory (code, the input, its rows
  of the weights) before reset, as Mig3's tests load their memory. Fetching them over the
  NoC (loads or DMA) is a later step, and a comparison: data local against data fetched.
- **Results:** each PE stores its 4 outputs to shared memory, then arrives at the barrier;
  hart 0 waits for all four, checks the outputs, prints the cycles and ends the run.

## The chunks, for now

1. This page.
2. Mig6Core: a copy of Mig3's core (rtl/design/mig3 without Mig3Cpu and its devices),
   renamed and nothing else; Mig3 stays as it is (done 2026-11-15: sv2v of Mig6Core and
   Mig3Core identical but for the names). The `@kb:` tags still point to Mig3's records.
3. Mig6Pe without the network: core and local memory, a `HART_ID` parameter that `mhartid`
   reads; a testbench for N cores; a program that prints its hart ID, on one PE.
4. The same program on four PEs (2 x 2), every hart ID exiting once.
5. The network interface (rtl/lib/block/noc): the library's memory channel to NoC packets
   and back, a library block with its own test; the same block at the memory edge.
6. Mig6Pe with the network interface; Mig6: four PEs, NocMesh, the shared memory at the
   edge; a program where every hart writes its ID to shared memory and arrives at a barrier.
7. The layer on four PEs, outputs checked, cycles against one Mig3.
8. Then the engine in a PE (a small int8 matrix unit, the systolic sketch in rtl/lib/ai),
   number formats (OCP MX, FP8), softmax and normalization.

## Open questions

- **Ordering of a PE's stores and its barrier:** settled for now by one request channel
  (see What travels on the NoC). If requests are ever spread over several virtual channels
  for speed, or a PE writes to more than one destination, they need ordering again: the
  network interface answers writes (an acknowledgement) and `fence` waits for them.
- **Other PEs' local memories** as address windows over the NoC (the same protocol): when
  chained layers need to pass data from PE to PE.
- **The packet format:** a request or an answer as NoC packets (the library's NoC owns the
  flit format, by macros), how many flits a line takes, which fields the head carries.
- **The shared memory's window** and atomics through it (see the address map).
- **Ending a run and printing with four cores:** semihosting through hart 0 only, or each
  PE's debug port; the testbench's view of four halts.
- **Configuration:** a Mig6 configuration (YAML, as Mig3's) once the shape settles.
- **The core's caches in a PE:** keep Mig3's, or a simpler local memory without them.

## References

Systems closest to this shape (cores with local memories and DMA, connected by a network,
no cache coherence): the PULP cluster and Snitch, and Occamy (many Snitch clusters on a
network), from ETH Zurich and Bologna's PULP platform. For the engine and attention later:
PULP's ITA (integer softmax for quantized attention), RedMulE (a matrix engine beside a
RISC-V cluster), Berkeley's Gemmini.
