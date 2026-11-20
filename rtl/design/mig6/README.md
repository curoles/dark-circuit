# Mig6: Mig3 cores on a network on chip, toward an AI chip

**Status: a prototype, being explored.** This page is the working plan, not a specification:
every choice below is "for now", made to get a first system running and measured, and any of
them may change as we learn. Open questions are listed at the end; decisions that settle get
kb records, as elsewhere in the project.

Mig6 is the AI-chip line of the roadmap: built from Mig3 (not from Mig4 or Mig5), no
operating system, no MMU, physical addresses, RV32. It is not a commercial product: the only
consideration is convenience for developing numeric and AI library blocks and for AI
experiments. It gives a home to library blocks that have none yet: the network on chip
(rtl/lib/block/noc), the far atomics (AtomicUnit), the DMA. Mig6's core is Mig3's without
P (packed SIMD): the engine in each PE does the int8 work, P stays in Mig3 and returns on
an RV64 core (kb rtl/design/mig6/no_p).

## The first target

One workload defines the first milestone: the int8 fully connected layer of the int8 kernel
(sw/riscv/kernels/int8_fc, publications/2026-11-int8-kernel.md), 64 inputs and 16
outputs, run on four PEs at once, every output compared with the plain-C reference, the
cycles compared with one Mig3: 9 220 cycles in plain C (Mig6 has no P; Mig3's P version
takes 2 560). Reached 2026-11-19 (test design_mig6_fc_layer): one PE 9 270 to 9 370
cycles, four PEs 2 525 to 2 545, 3.7 times faster, every output as the reference's.

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

- **Requests,** from a PE to the shared memory: read, write, atomic, LR and SC, with the
  address, the operation, and the data and strobes of a write.
- **Answers,** from the shared memory back to the PE: the data of a read or an LR, the old
  value of an atomic, the status of an SC.
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
    WRITE   | zero 12 | data 32 | strb 4 |       (body; an SC's the same)
    ATOMIC  | zero 10 | operand 32 | atop 6 |   (body)

  answers, 39-bit flits:
    DATA    | dest 4 | op 3 | data 32 |
    ACK     | dest 4 | op 3 | status 32 |       (an SC's)
```

- **A word at a time:** a request reads or writes up to a word (32 bits, 4 strobes). Lines
  would be new opcodes of more flits, when a cache needs them.
- **One or two flits:** READ, LR and CBO are a head alone, WRITE, SC and ATOMIC a head and
  a body. An answer is one flit: the word of a READ or an LR, the old word of an ATOMIC
  (DATA), an SC's status (ACK: RISC-V's SC result, 0 success, 1 failure, what the core
  writes to rd; as AXI answers a write on B, OKAY or EXOKAY).
- **LR and SC are opcodes,** the exclusive READ and WRITE (the request channel's
  `req_excl`): the head has no bit left for a flag (48 of 48).
- **No IDs:** an answer goes to the request's `src`. A PE's requests and answers stay in
  order, so a PE matches answers to requests by counting. This holds while a PE talks to one
  destination (see Open questions).
- **An opcode list per network,** 3 bits each: requests READ, WRITE, ATOMIC, CBO, LR, SC;
  answers DATA and ACK (an SC's; later acknowledged writes). The free codes are room for
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
  Answers have no ready, so a request that is answered is taken only when its answer has a
  place: at most D owed (a FIFO of their sources, a FIFO of answers waiting for a credit).
- **The exclusive monitor** is in Mig6MemNetIf, where every request to the shared memory
  passes with its source: a reservation per PE (a word). An LR reserves; any write, atomic
  or successful SC of the word ends every reservation of it; an SC is decided when no
  answer is in the memory, so its ACK, made there, goes behind the answers before it (kb
  rtl/design/mig6/far_lr_sc).
- **Backpressure is the credits:** while D answers are owed, Mig6MemNetIf takes no
  request, returns no credit, and the wait spreads back router by router until a PE's Mig6PeNetIf
  holds `req_ready` low. Answers drain on their own network, so it ends.

## A PE: Mig6Pe

```
  Mig6Pe:
    Mig3 core: data, local --------------------+--> local memory (a scratchpad)
               I-cache misses --> address -----+    (fixed priority: the core's data first,
               D-cache, far   --> decode       |     the I-cache's misses, the DMA)
                                    |  +-------+
                                    |  |    +--> network interface --> router
                                    |  |    |    (round-robin: the core, the DMA)
                                    +--|----+
                                    +--|--> DMA's registers
               DMA ---> address -------+
                        decode  ------------+
```

- **One core a PE, for now.** A PE may later get a matrix engine or a second core without
  changing the grid.
- **Local memory, a scratchpad:** code and private data, private to the PE. The core's loads
  and stores to it skip the D-cache: they go on a data port of their own, answered in the
  clock after the request as a cache hit is, and no cache holds a copy, so the PE's DMA (and
  later its engine) can write it with nothing going stale. Code still comes through the
  I-cache, whose misses share the memory's port; the core's data wins it (ReqMux by fixed
  priority, so the core's ready never depends on the address). The D-cache stays, for what
  is far: regions behind the network that may be cached (none yet: the cached alias below,
  when a measured case needs it). Arm's Cortex-M7 and Cortex-R5 pair TCMs and caches the
  same way (kb rtl/design/mig6/scratchpad).
- **A DMA:** the library's DmaSifive (SiFive's PDMA map, sw/riscv/drivers/dma.h), its
  registers the region dma; its done and error are sources of the PE's PLIC (the library's
  Plic, sw/riscv/drivers/plic.h, the region plic), whose one context is the core's machine
  external interrupt (kb rtl/design/mig6/plic). Its memory side and the core's memory port
  reach the local memory and the network interface through a small crossbar of ReqDemux
  and ReqMux, so the core works on local memory while the DMA waits for the network (kb
  rtl/design/mig6/dma). A word a transaction, one in flight, for now: the measurements in
  chunk 8 say what to improve.
- **Network interface:** the PE's door to the NoC; requests to the shared memory leave
  through it as packets, answers come back.
- **The same program on every PE** (SPMD): each finds its part from `mhartid`, the RISC-V
  hart ID, a parameter of the PE (Mig3 reads 0 today).
- **Address decode by the memory map:** the region's target (`pma_of`, see The memory map)
  sends an access to the local memory or to the network interface.

The modules around it:

```
  Mig6 (the top, for simulation):
    Mig6PeGrid: PE p = Mig6Pe g_pe[p].u_pe, node (p % MESH_X, p / MESH_X)
                Mig6Noc: the two meshes
         || the edge link
    the shared memory: Mig6MemNetIf --> AtomicUnit --> SimLatencyRAM
```

Mig6PeGrid computes each PE's hart ID and node, so a PE and its node always agree; what sits
at the grid's edge (one shared memory now) is the top's.

## Memory: why no coherence and no L2 yet

Coherence is a problem of copies: it arises only when two places hold the same data and one
writes it. Mig6 keeps one copy of everything, for now:

- **Local memory is private, and no cache holds it:** a scratchpad on the core's data
  port (code is copied into the I-cache, read only, as code always is).
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
  in every PE (one binary for all); not cacheable: a scratchpad on the core's data port;
  reservable (LR/SC: the core's own reservation, one hart, until a PE's DMA writes it); no
  AMOs (no AtomicUnit in front of it).
- **plic** at `0x0C000000`, 4 MiB (the spec's map up to context 0's claim register): the
  PE's PLIC; io, never cached; target devices.
- **dma** at `0x0C420000` (Mig3's offset), 4 KiB a channel, one channel: the PE's DMA's
  registers; io, never cached; target devices (the core's memory port to the DMA's register
  port; AddrDecode tells the two devices apart).
- **shared** at `0x80000000` (where RISC-V platforms put main memory), 1 MiB: the shared
  memory at the mesh's edge, through the PE's network interface; never cached (one copy);
  AMOs (the AtomicUnit in front of it); reservable, LR/SC done at the memory by its
  exclusive monitor (a reservable region behind the network: the core sends them far).
- **Other PEs' local memories** over the NoC: not needed by the first target; later, as more
  regions with target net.

An access outside every region stops the run (Mig6Pe: `a_in_region`; later an access
fault).

## The layer on four PEs

- **Split by outputs:** each PE computes 4 of the 16 outputs, from its 4 rows of the weights
  and the whole input, with the plain-C kernel (Mig6 has no P).
- **Data, for now:** one binary in every PE's local memory; every hart makes the same data
  there (the generator of Mig3's test, the whole layer, though it needs only its rows)
  before the first barrier, so the layer reads only local memory. Fetching the data over
  the NoC (loads or DMA) is a later step, and a comparison: data local against data
  fetched.
- **Results:** each PE stores its 4 outputs to shared memory (one word), then arrives at the
  barrier; hart 0 waits for all four, checks the outputs against its own whole-layer run
  and prints the cycles: one PE's (that run) against four PEs' (first barrier to second, its
  view: the slowest PE, the stores and the barrier); then every hart exits (see Ending a
  run). Each PE's rows take 2 425 to 2 500 cycles, the stores and the barrier about 90
  (kb test/design/mig6/fc_layer).

## Ending a run, for now

Every hart ends its program with a semihosting exit; each PE's debugger in the testbench
(test/design/mig6/tb) serves its semihosting calls, prints included.

- **A status other than 0** fails the run at once, whichever hart it was.
- **Status 0:** the hart's ID comes with the exit, in a2 (Mig6's exit puts `mhartid` there,
  test/design/mig6/mig6_exit.c: the debug port reads registers, not CSRs). The testbench knows
  how many harts there are; the ID must be one of them, must not have exited before, and must
  be the HART_ID of the PE that exited. When every hart has exited, the run passes.
- **`+max_cycles`** without that end fails the run, naming the harts that have not exited.
- **Timeouts inside a program**, so that it can say what it waited for: `semihost::Timeout`
  (sw/riscv/semihosting/semihost_timeout.hpp) on the semihosting clock, SYS_CLOCK. The
  testbench answers with simulated time, a centisecond of `+clocks_per_cs` clocks (default
  100), so a timeout in milliseconds is a few thousand clocks here and real time on QEMU.
  Each reading halts the core for the debugger; a loop whose cycles are measured takes its
  deadline from the `cycle` CSR instead (the barrier).
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
   edge (done 2026-11-18: Mig6PeGrid and Mig6, TbMig6 runs Mig6, every program's output
   unchanged); a program where every hart writes its ID to shared memory and arrives at a
   barrier (done 2026-11-18: test design_mig6_barrier, every hart sees every ID after it;
   the barrier takes 50 to 88 cycles, the PE next to the memory first; programs' -march
   rv32ima).
7. The layer on four PEs, outputs checked, cycles against one Mig3 (done 2026-11-19: the
   kernel moved to sw/riscv/kernels/int8_fc with a rows version; P out of Mig6, kb
   rtl/design/mig6/no_p; test design_mig6_fc_layer, 3.7 times one PE; the data made by each
   hart in its local memory, not preloaded by the testbench).
8. A DMA in each PE, so that the weights can start in shared memory and each PE fetches
   its part; cycles against the run with local data. In steps:
   a. The local memory as a scratchpad on the core's data port, the D-cache for far regions
      only (done 2026-11-19: ReqMux by fixed priority, kb rtl/lib/block/req_mux/fixed_priority
      and rtl/design/mig6/scratchpad; fc_layer's one PE 9 234 cycles instead of 9 314, its
      misses gone).
   b. The DMA (the library's DmaSifive, its registers the region dma, polled): the PE's
      requesters and targets as a 2 x 2 crossbar of ReqDemux and ReqMux (core and DMA, local
      memory and network interface), so the core works on local memory while the DMA reads
      the network (done 2026-11-20: kb rtl/design/mig6/dma; test design_mig6_dma_check, 320
      bytes shared to local: 1 122 cycles for the PE one router from the memory, about 1 775
      for two, 2 384 to 2 536 for three; local to local 424; so a round trip, a word at a
      time, sets the speed, about 8 cycles a router, not the four PEs' contention). The PLIC
      in each PE, the DMA's done as an interrupt (done 2026-11-20: kb rtl/design/mig6/plic;
      test design_mig6_irq_check, 64 bytes local to local: done seen polled 108 cycles after
      run, the handler entered at 111, main back at 182: the interrupt comes as fast as
      polling sees done, the handler's claim, clear and complete cost about 70). Then: the
      layer with its weights fetched by DMA, fetch and compute timed; local LR/SC by a
      monitor at the local memory's port, where the core's and the DMA's writes meet (until
      then a DMA write to the local memory does not end the core's reservation); then what
      the numbers ask (more reads in flight, bursts on the network).
   c. The cached alias of the shared memory (a region, the D-cache's first use): the weights
      by loads through the D-cache, a third way to compare.
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
  the reserved word does not end it, and an SC would succeed when it must fail. Decided
  (2026-11-18), in two steps. First: the shared region is not reservable, and an LR or SC
  outside a reservable region stops the run (Mig6Atomic: `a_lr_sc_reservable`; later an
  access fault). Then LR/SC done at the shared memory: the library's channels carry
  `req_excl` and `req_rsp` (kb rtl/lib/block/answered_writes, rtl/lib/block/cache/exclusive),
  the network LR and SC with Mig6MemNetIf's monitor (the library's ExclusiveMonitor),
  and the core sends LR/SC far to a region reservable but not cached; the shared region is
  reservable (done 2026-11-19: kb rtl/design/mig6/far_lr_sc; test design_mig6_cas_check,
  four harts count to the same total with compare-and-swap as with amoadd). AMOs already
  cover barriers, counters, flags and locks; LR/SC adds compare-and-swap. In a PE's local
  memory LR/SC syncs nothing (one hart, no interrupts), but it works, by the core's own
  reservation; when a PE's DMA writes the local memory (chunk 8), that reservation goes:
  every LR/SC far, a monitor in front of the local memory too.

## References

Systems closest to this shape (cores with local memories and DMA, connected by a network,
no cache coherence): the PULP cluster and Snitch, and Occamy (many Snitch clusters on a
network), from ETH Zurich and Bologna's PULP platform. For the engine and attention later:
PULP's ITA (integer softmax for quantized attention), RedMulE (a matrix engine beside a
RISC-V cluster), Berkeley's Gemmini.
