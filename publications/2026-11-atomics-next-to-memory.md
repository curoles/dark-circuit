# Atomics next to the memory: my core sends AMOADD as a load

*November 2026. Igor Lesik. Code: [dark-circuit](../README.md), an open library of hardware
blocks and the small RISC-V cores built from them.*

An atomic memory operation reads a word, changes it and writes it back, and nothing else may
touch the word in between. RISC-V's `amoadd.w rd, rs2, (rs1)` adds rs2 to the word at rs1 and
returns the old value in rd; counters, locks and reference counts are built on such
instructions. The obvious place to do the read-modify-write is the core: load, add, store,
with the pipeline held so nothing comes between. This place seems obvious because we are
used to thinking of the core's pipeline as the place where instructions are executed. We
project that picture onto the design we make, and the picture, not the problem, makes the
choice. An AMO is an instruction, but what it changes is memory, and memory is shared.

I did it elsewhere. My core sends an AMO as a load with a tag that says which operation; a
block next to the memory does the read, the operation and the write; the caches on the way
step aside. The core came out simpler, not more complex: no new state in the pipeline,
0.4 % more area, the clock unchanged. This note explains why, and how the pieces fit.

The core is Mig3, my 5-stage in-order RISC-V core (RV32IM with Zbb, now the A extension),
with an instruction cache and a write-through data cache in front of one memory.

## 1. Atomic with respect to whom?

On a core alone with its memory, any way of doing an AMO is atomic: nothing else writes the
memory. The question only gets hard when something else does, a DMA engine or a second
core. Then an AMO done in the core as a load, an add and a store can be split:

```
clock     1         2         3
core      read X=5  add       write X=6
DMA                 write X=100
```

The DMA's write is lost: X ends at 6, as if the DMA had never written. Done atomically, X
would end at 100 (the DMA's write after the AMO) or 101 (before it). The core cannot prevent
this by holding its own pipeline; the other writer does not see the core's pipeline at all.

Mig3 has one core and no DMA yet (the library has a DMA block now; Mig3 does not use it
yet). But the chips this library is heading for have both: a next core with an L2 cache,
and a chip for AI work with several cores and DMA engines. I wanted atomics that stay right
when those come, without redoing the core.

## 2. Four places to do it

- **In the core.** A small state machine in the execute stage: read, compute, write, the
  pipeline held for three clocks or more. Not atomic once another agent writes memory.
- **Split in decode.** The AMO becomes two micro-operations, a load and an operation with
  a store, through a hidden register. The same problem, plus a sequencer and two retired
  instructions to merge into one.
- **In the L1 data cache.** The cache owns the line through a coherence protocol, so
  nobody else can write it while the cache does the operation. Rocket does this, with an
  ALU in its data cache. Right for caches that own their lines; Mig3's write-through cache
  owns nothing.
- **Where every agent's accesses meet.** The point of coherence: in front of the memory
  in Mig3, at the L2 in the next core, at the cache slices or memory controllers in the AI
  chip. Whatever writes the memory passes there, so one block there makes the operation
  atomic for everyone.

I took the last one. It is also what the buses I care about define: AXI5 has atomic
transactions (the AWATOP field), TileLink has arithmetic and logical operations carried to
the outer level, and Arm CHI lets the home node do an atomic ("far atomics").

## 3. A request with an operation: atop

The library's request channels got one more field, `atop`, the operation. Its values are
AXI5's AWATOP, so that an AXI adapter will be plain wiring, though the package itself knows
nothing about AXI:

```systemverilog
typedef logic [5:0] atop_t;   // as AXI5 AWATOP
ATOP_NONE    = 6'b00_0000;  // an ordinary request
ATOP_LD_ADD  = 6'b10_0000;  // old + data
ATOP_LD_CLR  = 6'b10_0001;  // old & ~data
ATOP_LD_EOR  = 6'b10_0010;  // old ^ data
ATOP_LD_SET  = 6'b10_0011;  // old | data
ATOP_LD_SMAX = 6'b10_0100;  // signed max
...
ATOP_SWAP    = 6'b11_0000;  // data
```

Every one answers with the old value; the request's data is the operand. The nine RISC-V
AMOs map one to one, with a single twist: AXI has no AND, only CLR, "clear the bits of the
operand". So for `amoand.w` the core sends `~rs2`, and `old & ~(~rs2)` is the AND. One
inverter in the core keeps the encoding AXI's.

## 4. AtomicUnit, next to the memory

AtomicUnit sits in front of a memory level. Ordinary reads and writes pass through it as
they come. An atomic request does this:

- it waits until every read that passed before it is answered (so answers stay in order),
- reads the word,
- computes the new value when the old one comes back,
- writes it, and answers with the old value.

From the moment it takes the atomic until its write is taken, it takes no other request.
That is the whole atomicity: at this point every access to the memory passes, and none
passes while the operation is in flight. The state machine:

```systemverilog
case (state)
    IDLE:  if (take_atomic)   state <= READ;
    READ:  if (mem_req_ready) state <= WAIT;
    WAIT:  if (mem_rsp_valid) state <= WRITE;
    WRITE: if (mem_req_ready) state <= IDLE;
endcase
```

The operation itself is the library's ALU, the one the cores use: ADD, ANDN (which is CLR),
XOR, OR, and the min and max of the Zbb extension. A swap needs no ALU.

## 5. The caches step aside

An atomic's word may be in the data cache, and a write-through cache cannot do the
operation: it owns nothing, and it never sees the new value. So a cache treats an atomic
as a load that must reach the memory exactly as asked:

- **it never hits:** the lookup runs as for any load, but a hit does not answer;
- **it goes down unchanged:** the exact address and size, the operand, the atop;
- **its answer is not kept:** the old value goes to the core, nothing is written into
  the cache;
- **the line it hits is dropped,** because the only copy the cache could keep is the old
  one.

When to drop took a moment's thought. The cache drops the line in the clock the memory
takes the atomic's read. In that clock the cache takes no new request, so nothing can read
the stale line, and the next access misses and fetches the new value, which AtomicUnit
writes before it takes anything else. Dropping when the answer comes back would have been
wrong: in that clock the cache does take a request, and it would read the old line (the
same clock as in my note *Replay instead of refuse*).

## 6. The core: an AMO is a load

In the core, decode turns all nine AMOs into one kind: a load of the word at rs1 into rd,
which also reads rs2. The load/store unit sends it as a word load with its atop and its
operand:

```systemverilog
assign amo   = load &&
               is_atomic(dec.atomic.atop);
assign clear = dec.atomic.atop == ATOP_LD_CLR;
// the operand: clear ? ~rs2 : rs2
```

The old value comes back as a load's data and goes to rd. Everything else in the pipeline
already knows loads: forwarding, the stall when the next instruction needs the result, the
retire. There is no state machine in the execute stage, no second ALU, no store behind the
load. Two details follow the spec rather than the hardware: a misaligned AMO traps with
"store/AMO address misaligned", not the load's cause, though the core treats it as a load;
and the ordering bits aq and rl are ignored, since one hart issues everything in order.

The cost, measured with Yosys on the open sky130 cell library: the clock stays at 5.5 ns,
the area grows 0.4 % (the atop through the data cache and the decode of the AMOs).

## 7. Checking what the core never sees

My testbench checks every retired instruction against a model, including the memory it
reads and writes. An AMO is awkward there: the core reports the old value, but it never
sees the new one, which is made next to the memory. Computing it in the core only for the
trace would cost an ALU in the last stage for nothing the hardware needs. So the checker
does it: from the old value and rs2 it computes the new word, and it expects that word as
the first write the memory takes after the AMO retires (AtomicUnit takes nothing before
that write).

Then the usual layers:

- **AtomicUnit alone:** random reads, writes and atomics of all nine operations against an
  ideal memory, every answer and the memory at the end compared.
- **The cache:** atomics that hit (and must drop the line) and atomics that miss, the
  memory request checked as asked.
- **The core:** riscv-tests' rv32ua, every AMO after a store and before a load of its
  word, also after a miss, with the checker computing each new word.
- **Mutants:** deliberately broken versions of each block, every one caught.

## 8. What it leaves out, and what it costs

- **LR/SC is still in the core.** Its reservation (load-reserved, store-conditional) lives
  in the execute stage, enough for one hart. With a second agent it moves next to
  AtomicUnit, as an exclusive monitor that the writes of the others break: AXI's exclusive
  accesses.
- **No atomics to devices.** An AMO to the interrupt controller or the timer is caught by
  an assertion; a later core turns it into an access fault.
- **Two operations unused.** AXI5 also has AtomicStore (the operation without an answer,
  for an AMO whose rd is x0) and AtomicCompare (compare-and-swap); RISC-V's AMOs do not
  need them yet.
- **Latency.** An AMO always goes to the memory and back, twice (a read and a write). For a
  counter that only one core uses, an atomic in an owning L1 cache would be faster. Under
  sharing it is the other way round: the line does not travel between caches, the
  operation goes to the data. CHI allows both for that reason; a core with coherent caches
  can choose per access later.

## 9. How it compares

- **Rocket** (and most cores with coherent L1 caches): the AMO ALU is in the L1 data
  cache, "near" atomics, possible because the cache owns the line.
- **TileLink:** arithmetic and logical operations are messages of the protocol, done
  where the data lives.
- **AXI5:** atomic transactions with AWATOP, the encoding I borrowed.
- **Arm CHI:** atomics near or far, the far ones at the home node, after it invalidates
  other copies.
- **GPUs:** global atomics are done at the L2, next to the memory, for the same reason as
  here: many agents, one place where they all meet.

Mig3's version is the simplest of these: one memory, one block in front of it, caches that
step aside. The block moves with the memory hierarchy (to the L2, then to the slices), and
the core does not change.

The code is in the repository: `rtl/lib/block/atomic` (AtomicPkg, AtomicUnit and its test
in `test/block/atomic/atomic_unit`), the caches' drop in
`rtl/lib/block/cache/cache_control`, the core's side in `rtl/design/mig3/mig3_decode.sv` and
`mig3_lsu.sv`. The knowledge-base records behind this note are
`kb/rtl/lib/block/atomic/design.yaml`, `kb/rtl/lib/block/cache/atomic.yaml` and
`kb/rtl/design/mig3/amo.yaml`.

## Appendix 1: questions from readers

Readers asked sharp questions after this note was published; here they are, each quoted,
with my answers. The note describes Mig3: one in-order hart and one memory. Several of the
questions are real limits of that simple version, and the answers say so.

One thing first, because several questions turn on it: "an AMO is a load" describes only
the core's pipeline. Inside the core an AMO takes the load's path: it is sent like a load,
and the old value comes back like a load's data and goes to rd. Outside the pipeline
nothing treats it as an ordinary load: the request carries its operation, so a cache never
answers it from a hit and keeps no copy of the answer, and AtomicUnit writes the new value.

### 1. Removing other cores' copies

> What is this scheme is responsible for removing shared L1 copies from other cores?

In Mig3 there is only one L1, and it drops its own copy of the line when the atomic passes
through. With several cores there are two cases. In a multi-core design without cache
coherence, shared data is never cached, so there are no other copies to remove. With
coherent caches, the coherence protocol does it: the home node invalidates the sharers, or
recalls the owner, before it performs the operation. That is what Arm CHI's far atomics
do, and the block that does the read-modify-write sits at the home node, the natural place
to invalidate first.

### 2. aq and rl

> What guarantees AQ/RL semanics? In-order in one hart doesn't help ordering traffic
> generated by other harts.

aq and rl constrain the order in which this hart's own accesses become visible relative to
its AMO; they never order other harts' traffic. That order is set by the single point
where all accesses meet, which is where the AMO is performed. In Mig3 every access goes in
program order through one path to one memory, so a hart's accesses become visible in
order and aq and rl hold without any logic of their own. That stops being true as soon as
accesses can take different paths: local and shared memories, different routes through a
network, a store buffer. Then writes need acknowledgements, and the core must wait for its
outstanding accesses at aq, rl and fence. The note's one line, "ignored, since one hart
issues everything in order", was too short.

### 3. Permissions, faults and watchpoints

> Treating AMO as "load" is dangerous if MMU is in play: write permissions are not
> checked, nothing will prevent overriding read-only pages ; faults will be generated
> without writes indication -> COW patterns will break in OS ; hardware watchpoints will
> not rigger on AMOs

Agreed, and this is the line between the datapath and the access. For permissions, faults
and triggers an AMO is a store: it needs write permission as well as read, it must fault
as a store/AMO page fault, so that copy-on-write and the dirty bit work, and hardware
watchpoints must see it as the store it is. Mig3 has no MMU and no triggers, so none of
this is checked today; it already reports a misaligned AMO with the store/AMO cause, not
the load's. A core with an MMU marks an AMO in decode as two things at once: a load for
the datapath, a store for every check.

### 4. A frozen memory port

> AMO have to freeze the memory port for 2 roudtrip duration, so all cores in the system
> even accessing unrelated lines will stall. Can be relaxed by adding compactor but still
> every memory access will pay the price.

True for Mig3's AtomicUnit: it takes no other request while an atomic is in flight, the
simplest correct version for one memory with one-clock latency. In front of a shared cache
the operation locks only its line, not the port: an address compare against the atomics in
flight, the same kind of check a cache already makes against its outstanding misses. It
runs beside the lookup, so an unrelated access pays a little area, not a round trip, and
only accesses to the same line wait, as they would have to anyway. With the cache split
into slices by address, only one slice ever sees the atomic. And there the
read-modify-write is a read and a write of the cache's SRAM, not two trips to DRAM.

### 5. Forwarding from the store buffer

> loads can no longer forward from store buffer -> RAW loads will be stalled for the
> memory roundtrip.

Mig3 has no store buffer (a write-through cache, everything in order), so nothing changes
there. In a core with one, both halves of the point hold. Older stores to the word, and all
older stores when the AMO has rl, must drain before the AMO goes out. A younger load of the
same word can not forward from the AMO, because the core never sees the new value: it goes
to memory and waits for the round trip. That cost is real and comes with far atomics. It is
the trade-off of the note's section 8: for a counter only one core uses, an atomic in an L1
that owns the line is faster; for synchronization variables shared between cores, which
miss in the L1 under sharing anyway, the far atomic wins. Arm CHI allows both for this
reason.

### 6. LR/SC and the writes of others

> if LR/SC lives only in execution pipeline, how another core write (or DMA) will break
> reservation?

It does not, and that is a real gap. Section 8 lists it as an open item: a reservation in
the pipeline is enough while the core is the only agent. Since the note was written Mig3
has got a DMA engine, and today a DMA write to a reserved word does not clear the
reservation, so an SC can succeed when it should fail. The fix is the one the note plans:
an exclusive monitor next to AtomicUnit, where every write to the memory passes, so that a
write from any other agent, a core or the DMA, clears the reservation. That is how AXI's
exclusive accesses work.
