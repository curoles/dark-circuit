# Replay instead of refuse: getting 0.5 ns back

*November 2026. Igor Lesik. Code: [dark-circuit](../README.md), an open library of hardware
blocks and the small RISC-V cores built from them.*

I made my CPU's caches faster by one clock per miss, and the obvious way to do it made the
whole CPU 8 % slower. The fix is a small, well-known trick: instead of refusing a request
that would see stale data, take it, and let it look again one clock later. This is the
story, with the numbers.

The CPU is Mig2, a 5-stage in-order RISC-V core (RV32IM with Zbb, branch prediction). It has
an instruction cache and a data cache, both 2-way skewed-associative with 64 lines of one
word, in front of one memory. Timing numbers are from Yosys and ABC mapped to the open
sky130 cell library: estimates without wires, good for comparing two versions of the same
design, not for promising a frequency.

## 1. The wasted clock

A cache sits between the CPU and memory. The CPU sends it requests, one address at a time.
If the cache has the address (a *hit*), the answer comes in the next clock. If it does not
(a *miss*), the cache asks memory for the line, waits, and when memory answers it does two
things in the same clock: it gives the word to the CPU, and it writes the line into its own
storage so that the next request for it hits. That clock is the *refill clock*.

My cache followed one simple rule: while a miss is being served, take no new request. And
"being served" included the refill clock. So the CPU, which usually had its next request
ready, waited one more clock for nothing:

```
            clock 1        clock 2        clock 3              clock 4
CPU         asks for A     B waits        B waits              B is taken
cache       A misses:      waits for      refill: writes A,    looks up B
            asks memory    memory         answers A
memory      takes the      ...            answers A
            read of A
```

In clock 3 the cache does its two refill jobs, but it could also take B: nothing else is
busy. Taking it there saves one clock on every miss. In a pipelined CPU a waiting cache
stops the whole pipeline, so one clock per miss is one clock of the whole program per miss.

## 2. Why the obvious change is wrong

So: take a request in the refill clock. The catch is in the cache's memories. They are
*read-first*: in a clock where a place is written, a read of the same place returns the old
contents (the new value is there from the next clock on). That is how most SRAMs behave, and
how my RAM blocks are written.

Now picture the refill writing line A into set 5 of the cache, where line V used to be. In
the same clock the cache takes request B, which also lives in set 5. B reads set 5 and gets
the old contents: line V.

- If B is a load of A, it sees V's tag and misses, though A arrives at that very edge.
  The cache fetches A again: wasted time, and in an associative cache maybe a second copy of
  A in the other way.
- If B is a store to V's address, it *hits* the old copy of V, and the cache writes V's
  data, with B's bytes merged in, into set 5. Which now holds A. The cache has A's address
  with V's data: silent corruption.

This is not a theory. With the change and no guard, two of Mig2's test programs fail.

## 3. Fix 1: refuse that request

The guard is simple to state: in the refill clock, do not take a request that is at the
place the refill writes. Every other request can be taken, because it reads lines the
refill does not touch. For a set-associative cache "the place" is the set; for my skewed
cache it is the index in the way being filled.

In the cache's control the guard became one term of `req_ready`, the signal that tells the
CPU "I take your request now":

```systemverilog
// a miss is served: no request, except in the refill clock away from the refilled place
assign wait_busy = waiting && (!mem_rsp_valid || fill_conflict);
```

`fill_conflict` compares the request's index with the refilled line's index. Cycles went down
exactly as hoped. Then I ran synthesis, and the longest path went from **6.2 ns to 6.7 ns**.

The new longest path:

```
pc register (fetch's address)
  -> the skewed cache's index hash
  -> compare with the refilled line's index    fill_conflict
  -> req_ready of the instruction cache
  -> fetch: "the cache took my request"
  -> the multiplexer choosing the next pc
  -> pc register
```

Before, `req_ready` came from a few flip-flops of the cache's own state. Now it waited for
the request's address to be hashed and compared, and fetch waited for `req_ready` before it
could choose the next pc. One clock saved per miss, paid for with 8 % of every clock.

## 4. Why: a late signal decided something everybody waits on

There is a rule I now keep in my library's design notes: a signal that arrives late in the
clock must not drive a global control in the same clock. The request's address is late: it
comes out of the logic that computes it. `req_ready` is global: fetch, and through it the
whole pipeline, waits for it. Plugging the first into the second made one long path out of
two short ones.

## 5. Fix 2: replay instead of refuse

The question is not "should the cache take B?". It is "what does B see?". So take B in the
refill clock, always, and deal with the stale read afterwards, from flip-flops:

```systemverilog
// B taken in the refill clock at the refilled place read the old line there
always_ff @(posedge clk)
    if (!rst_n) replay <= 1'b0;
    else        replay <= accept && refill && fill_conflict;

assign ram_rd  = accept || replay;      // the RAMs read again, at B's own index
assign look_ok = look && !replay;       // and the stale lookup does nothing
```

The compare is still there, but it ends in a flip-flop, `replay`, instead of in `req_ready`.
In the clock after, B's lookup does nothing (no hit, no miss, no write, `req_ready` is 0) and
the RAMs read B's place again, now with A in it. In the clock after that, B is looked up as
usual:

```
            clock 3 (refill)          clock 4 (replay)            clock 5
request B   taken                     -                           -
cache       writes A into set 5;      reads set 5 again;          looks up B: sees A
            B reads set 5: old V      nothing else happens
            replay <= 1
```

A request away from the refilled place is taken and looked up as in fix 1. A request at
that place gets its lookup in clock 5 in both fixes: in fix 1 it waited a clock before being
taken, here it is taken and replays. So the cycles are the same, clock for clock: all 105
traces of Mig2's test programs are identical between the two fixes.

The cost is one flip-flop, one gate on the RAMs' read enable and a multiplexer on their read
index (one per way). The longest path is **6.1 ns**, the same as before the change within
the estimate's noise, and now starts at the cache's tag RAM instead of at `req_ready`. Area
grew by 0.2 %.

## 6. The result

| Version | Longest path | Area | Cached Dhrystone | Cached towers | Cached qsort |
|---|---|---|---|---|---|
| Before (no request in the refill clock) | 6.2 ns | 244 804 µm² | 3 157 339 cycles | 399 210 | 179 845 |
| Fix 1: refuse at the refilled place | 6.7 ns | 241 807 µm² | 2 598 076 | 317 317 | 178 456 |
| Fix 2: replay | 6.1 ns | 245 259 µm² | 2 598 076 | 317 317 | 178 456 |

Dhrystone runs in 17.7 % fewer cycles, towers in 20.5 % fewer, at the same clock; qsort has
few misses and gains 0.8 %. Programs that bypass the caches (Mig2's cycle-counting tests run
uncached) keep their counts exactly.

## 7. What I take from it

- **Measure timing after every change, not at the end.** The cycle count looked great; the
  cost was in a place cycle counts cannot see. Synthesis took minutes and showed it.
- **Resolve hazards inside the pipeline, from flip-flops, not in the handshake.** A ready
  signal that depends on the request's contents is a path from one block's logic into
  another block's decisions. Taking the request and replaying it keeps `req_ready` simple.
- **Replay is a pattern, not a hack.** Out-of-order cores replay loads that speculated
  wrongly; caches with hit-under-miss decide "is this new request at a busy place?" in the
  lookup stage. My cache will need that question more often as it grows, and now it asks it
  in the right place. The library records it as a design pattern, next to the block that
  uses it.

## How I measured, and where the code is

- The change: [CacheControl](../rtl/lib/block/cache/cache_control/behave/cache_control.sv)
  (its gate-level version is next to it), shared by the library's three caches.
- Why, with the options rejected:
  [refill_take](../kb/rtl/lib/block/cache/cache_control/refill_take.yaml) and the pattern
  [replay](../kb/rtl/lib/block/cache/cache_control/replay.yaml).
- Timing and area: `make mig2_synth TECH=sky130` (Yosys, ABC, sky130 cells; the caches' RAMs
  as black boxes, as memory macros would be).
- Cycles: Dhrystone, qsort and towers from riscv-tests, gcc 12.2, `-O2`, on Mig2 with memory
  of latency 1, in Verilator.
- Correctness: the six cache tests check every clock against models that take requests in
  the refill clock and replay the conflicting ones (each test must see both), and changes
  the way bugs would make them (no guard, no replay, a replay that does not read again, the
  wrong index) are caught by the tests; without the guard two Mig2 programs fail.
