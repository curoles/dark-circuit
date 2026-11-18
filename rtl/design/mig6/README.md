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
                                +-----------+
                                |  shared   |  network interface,
                                |  memory   |  AtomicUnit, RAM
                                +-----------+
                                      |      edge link: node (1,2)
              +-----------+     +-----------+
              |  PE (0,1) |-----|  PE (1,1) |
              |  hart 2   |     |  hart 3   |
              +-----------+     +-----------+
                    |                 |
              +-----------+     +-----------+
              |  PE (0,0) |-----|  PE (1,0) |
              |  hart 0   |     |  hart 1   |
              +-----------+     +-----------+

  y grows north, as in NocMesh; every line is the NoC, two networks (Mig6Noc: a NocMesh
  each, routers and links): requests and answers; outside the PEs
```

- **A 2 x 2 mesh of PEs** (NocMesh, one slice): enough for a real parallel speedup and real
  network traffic (up to two hops with XY routing), small enough to simulate on a laptop.
  The mesh is parameterized; a larger grid is a parameter.
- **Shared memory on an edge link** of the mesh, outside the grid, so all four nodes are PEs:
  a network interface, AtomicUnit (atomics done next to the memory) and a RAM. It is node
  (1, 2), on the north link of PE (1, 1): XY routes go along X first, so every request
  reaches it through (1, 1). On the east link of (1, 1), as node (2, 1), the requests of
  (0, 0) and (1, 0) would leave the mesh at (1, 0)'s east edge instead.
- **Not fair, for now:** router (1, 1) takes its inputs in turn (round robin), and its
  south input carries PE 0's and PE 1's requests together, so PEs 2 and 3 get a third of the
  memory each, PEs 0 and 1 a sixth (in design_mig6_noc they finish about 35% later). The
  usual cures: arbitration by age or by source, or more memory ports.

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
- **Two networks, one per message class:** requests on one, answers on the other, each a
  NocMesh. If requests fill their network, answers still get through and free room, so the
  two never block each other (no protocol deadlock), by construction. Commercial chips do
  the same (AMBA CHI's channels, Intel's rings, Tilera, OpenPiton): on a chip wires are
  cheap, buffers and allocators are not, and each network gets its own width. Virtual
  channel classes in one network would need a router change; they may come later.
- **One virtual channel per network, for now,** so a PE's requests to the shared memory
  keep their order: they take the same XY path on the same channel, and AtomicUnit serves
  them as they arrive. A PE's result stores are in memory before its barrier `amoadd`,
  without acknowledgements of writes.

### The messages, for now

Mig6NocPkg (`mig6_noc_pkg.sv`) owns them, not the library and not Mig6Pkg: it moves to the
library once the format settles, after the layer runs. A message's head is the library's
(the route, `dest_x` and `dest_y`, which the routers read), then the package's fields.

```
  requests, 48-bit flits:
    head    | dest 4 | op 3 | src 4 | size 3 | addr 32 | cmo 2 |
    WRITE   | zero 12 | data 32 | strb 4 |       (body)
    ATOMIC  | zero 10 | operand 32 | atop 6 |   (body)

  answers, 39-bit flits:
    DATA    | dest 4 | op 3 | data 32 |
```

- **A word at a time:** a request reads or writes up to a word (32 bits, 4 strobes). Lines
  would be new opcodes of more flits, when a cache needs them.
- **One or two flits:** READ and CBO are a head alone, WRITE and ATOMIC a head and a body.
  An answer is one flit: the word of a READ, the old word of an ATOMIC.
- **No IDs:** an answer goes to the request's `src`. A PE's requests and answers stay in
  order, so a PE matches answers to requests by counting. This holds while a PE talks to one
  destination (see Open questions).
- **An opcode list per network,** 3 bits each: requests READ, WRITE, ATOMIC, CBO; answers
  DATA, and ACK, not sent yet (no acknowledgements of writes). The free codes are room for
  lines and error answers.

### The network interfaces, for now

Two, in rtl/design/mig6 with Mig6NocPkg: Mig6PeNetIf in a PE, Mig6MemNetIf at the shared memory.
Each faces the library's request channel, a word wide (valid/ready, read answers in order
with no ready), so anything that speaks it attaches: a core, a DMA through a `ReqMux`,
AtomicUnit and a RAM.

- **Mig6PeNetIf** turns a request into a head and a body flit, sent while the router has
  credits, and takes the request with its last flit. Answers go straight to the requester,
  credits straight back: it holds no answer and limits nothing. Mig6Pe picks the word of
  the core's line-wide port, as Mig3Cpu does for its devices (only uncached accesses of a
  word or less come).
- **Mig6MemNetIf** buffers request flits (the credits it gives), passes a request on to
  AtomicUnit and the RAM with its body, and drops CBOs (nothing caches the shared memory).
  Answers have no ready, so a READ or an ATOMIC is taken only when its answer has a place:
  at most D owed (a FIFO of their sources, a FIFO of answers waiting for a credit).
- **Backpressure is the credits:** while D answers are owed, Mig6MemNetIf takes no
  request, returns no credit, and the wait spreads back router by router until a PE's Mig6PeNetIf
  holds `req_ready` low. Answers drain on their own network, so it ends.

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

### Ways to cache shared data, case by case

Data that many reads use and few writes change (written in one phase, read over and over in
the next) is worth a fast copy. Two ways, both meant to be used, each where it fits:

- **Copy it into local memory:** read the shared data once (memcpy now, the PE's DMA later)
  into the local memory, which is private and cached as always; no coherence question at
  all. PULP's and Snitch's way (a DMA into a local scratchpad), and the plan of the DMA
  chunk.
- **A cached alias of the shared memory:** the same memory as a second region of the map,
  `cacheable: yes` (as MIPS's kseg0 beside kseg1). Mig6's D-cache writes through and does
  not allocate on stores, so no dirty line can overwrite another PE's words; only stale
  reads remain, and software removes them: `cbo.inval` of the range after the barrier that
  ends the writing phase (the bulk-synchronous way, as GPUs' non-coherent L1 caches). Flags
  and counters only by AMOs (they never hit) or through the uncached region: a load that
  spins on a cached copy would spin forever. One alias per address within a phase: a store
  through the uncached region does not update a copy cached through the other.

For now only the uncached region exists; the alias is one more row of the map when a
measured case needs it. Should shared data ever stay cached without such rules, coherence
comes back as a choice: a directory protocol (MSI/MESI).

## The memory map, for now

`cfg/mig6_pma.yaml`, PMA-style (physical memory attributes, as the RISC-V privileged spec
names them): every region with the properties hardware asks, each by name, so that no part
decides by "is it I/O?". `tools/pma_gen.py` checks the map (no overlaps, sizes powers of 2,
bases multiples of their sizes, an io region not cacheable) and generates Mig6PmaPkg
(`pma_of(addr)` for the caches, Mig6Pe and its assertions), `sw/riscv/mig6/mig6_pma.h` and
`mig6_pma.hpp` for programs, and the linker script `mig6.ld`.

- **local** at `0x00000000`, 64 KiB: a PE's local memory, code and data, the same addresses
  in every PE (one binary for all); cacheable; reservable (LR/SC: the core's own
  reservation, one hart); no AMOs (no AtomicUnit in front of it).
- **devices** at `0x0C000000`, 64 MiB: no devices in a PE yet; io, never cached.
- **shared** at `0x80000000` (where RISC-V platforms put main memory), 1 MiB: the shared
  memory at the mesh's edge, through the PE's network interface; never cached (one copy);
  AMOs (the AtomicUnit in front of it); not reservable yet (see Open questions).
- **Other PEs' local memories** over the NoC: not needed by the first target; later, as more
  regions with target net.

An access outside every region stops the run (Mig6Pe: `a_in_region`; later an access
fault).

## The layer on four PEs

- **Split by outputs:** each PE computes 4 of the 16 outputs, from its 4 rows of the weights
  and the whole input, with the P kernel of the article.
- **Data, for now:** the testbench loads every PE's local memory (code, the input, its rows
  of the weights) before reset, as Mig3's tests load their memory. Fetching them over the
  NoC (loads or DMA) is a later step, and a comparison: data local against data fetched.
- **Results:** each PE stores its 4 outputs to shared memory, then arrives at the barrier;
  hart 0 waits for all four, checks the outputs and prints the cycles; then every hart exits
  (see Ending a run).

## Ending a run, for now

Every hart ends its program with a semihosting exit; each PE's debugger in the testbench
(test/design/mig6/tb) serves its semihosting calls, prints included.

- **A status other than 0** fails the run at once, whichever hart it was.
- **Status 0:** the hart's ID comes with the exit, in a2 (Mig6's exit puts `mhartid` there,
  test/design/mig6/mig6_exit.c: the debug port reads registers, not CSRs). The testbench knows
  how many harts there are; the ID must be one of them, must not have exited before, and must
  be the HART_ID of the PE that exited. When every hart has exited, the run passes.
- **`+max_cycles`** without that end fails the run, naming the harts that have not exited.
- **Printing:** a line buffer per PE, so that the lines of PEs running at once never mix,
  however a program prints (a character a call, a string a call). Every line gets the hart's
  prefix, one PE or many:

  ```
  [hart 2] hartid: 2
  [hart 0] hartid: 0
  ```

  What is left in a buffer is printed at the hart's exit, and before a failure's message.

## The chunks, for now

1. This page.
2. Mig6Core: a copy of Mig3's core (rtl/design/mig3 without Mig3Cpu and its devices),
   renamed and nothing else; Mig3 stays as it is (done 2026-11-15: sv2v of Mig6Core and
   Mig3Core identical but for the names). The `@kb:` tags still point to Mig3's records.
3. Mig6Pe without the network: core and local memory, a `HART_ID` parameter that `mhartid`
   reads; a testbench for N cores; a program that prints its hart ID, on one PE (done
   2026-11-15: test design_mig6_mhartid).
4. The same program on four PEs (2 x 2), every hart ID exiting once (done 2026-11-15:
   TbMig6 with four PEs, line buffers with the hart's prefix).
5. The network interfaces, in rtl/design/mig6 for now: the one-VC mesh tested in the
   library (done 2026-11-16: NocMesh's test, 2 x 2 with one VC; it fixed NocSwitchAlloc
   struct for one VC); Mig6NocPkg, the messages (done 2026-11-16); a PE's network interface
   and the shared memory's, joined without a mesh, with a stand-in core in the testbench
   (done 2026-11-16: test design_mig6_net_if); then the 2 x 2 meshes with four stand-ins
   (done 2026-11-17: Mig6Noc, test design_mig6_noc, a shared counter's adds atomic).
6. Mig6Pe with the network interface; Mig6: four PEs, Mig6Noc, the shared memory at the
   edge; a program where every hart writes its ID to shared memory and arrives at a barrier.
7. The layer on four PEs, outputs checked, cycles against one Mig3; the testbench preloads
   each PE's weights and inputs into its local memory.
8. A DMA in each PE (the library's DmaSifive, sharing the network interface through a
   `ReqMux`, as in Mig3Cpu): the weights in shared memory, each PE fetching its part; cycles
   against the preloaded run.
9. Then the engine in a PE (a small int8 matrix unit, the systolic sketch in rtl/lib/ai),
   number formats (OCP MX, FP8), softmax and normalization.

## Open questions

- **Ordering of a PE's stores and its barrier:** settled for now by one request network
  with one virtual channel (see What travels on the NoC). If requests are ever spread over
  several virtual channels for speed, or a PE writes to more than one destination, they need
  ordering again: the memory side answers writes (ACK) and `fence` waits for them; answers
  from several destinations may also need IDs.
- **Other PEs' local memories** as address windows over the NoC (the same protocol): when
  chained layers need to pass data from PE to PE.
- **LR/SC on the shared memory:** a reservation lives in a core, so another PE's store to
  the reserved word does not end it, and an SC would succeed when it must fail; the shared
  region is not reservable until that is settled (an exclusive monitor at the memory,
  Zacas' compare-and-swap AMO, or an access fault).
- **The core's caches in a PE:** keep Mig3's, or a simpler local memory without them.

## References

Systems closest to this shape (cores with local memories and DMA, connected by a network,
no cache coherence): the PULP cluster and Snitch, and Occamy (many Snitch clusters on a
network), from ETH Zurich and Bologna's PULP platform. For the engine and attention later:
PULP's ITA (integer softmax for quantized attention), RedMulE (a matrix engine beside a
RISC-V cluster), Berkeley's Gemmini.
