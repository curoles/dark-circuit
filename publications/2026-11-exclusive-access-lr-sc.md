# Exclusive access on shared memory: LR/SC across cores, decided at the memory

*November 2026. Igor Lesik. Code: [dark-circuit](../README.md), an open library of hardware
blocks and the small RISC-V cores built from them.*

RISC-V has two ways to change a word in memory safely when others may change it too. An AMO
(`amoadd.w`, `amoswap.w`, ...) does the read, the operation and the write as one indivisible
step; my earlier note showed how my cores send it to a block next to the memory. The other
way is a pair of instructions, LR and SC, load-reserved and store-conditional:

```
retry:
  lr.w   t0, (a0)       # read the word, reserve it
  addi   t1, t0, 1      # any computation at all
  sc.w   t2, t1, (a0)   # write it, only if still reserved
  bnez   t2, retry      # t2 = 0: done; 1: someone came between
```

AMOs cover counters, flags, locks and barriers. LR/SC cover everything else that must read
a word, decide, and write: compare-and-swap, lock-free queues, any read-modify-write that no
single AMO does. C compilers turn `__atomic_compare_exchange` into exactly this loop.

This note is about where the reservation lives. In a core alone, the answer is easy. In
Mig6, a prototype of four small RISC-V cores on a network on chip sharing one memory, the
easy answer is wrong, and making it right touched more of the library than I expected.

## 1. What LR/SC promise

The specification's promise is short: an SC succeeds only if no other hart wrote the
reserved word since the LR. An SC that fails writes nothing and returns 1; the program
tries again. An SC may also fail for reasons of its own (a trap in between, a second LR),
which costs a retry, never a wrong result.

So whoever keeps the reservation must see every write to the word, from everyone.

## 2. The reservation in the core, and where it breaks

My cores keep it in the core: one reservation, a valid bit and a word address, set by an LR,
checked by an SC, ended by an SC, a trap or MRET. That is the whole of LR/SC in the core:
the LR is a load and the SC a store for the rest of the pipeline.

It is correct while the core is alone: nobody else writes. Mig6 is not alone. Its four PEs
each have their own core and local memory, and they share one memory at the edge of the
mesh:

```
clock   PE 0               PE 1
1       lr.w  X  -> 5
2                          sw   X <- 100
3       sc.w  X <- 6  ok?
```

PE 1's store goes over the network to the shared memory. PE 0's reservation is in PE 0's
core, which never sees that store. Its SC succeeds, X ends at 6, PE 1's write is lost. The
promise is broken without any wrong gate anywhere: the reservation is simply kept where the
other writer is invisible.

Until this was fixed, Mig6 did the honest thing: the shared region was marked not
reservable in the memory map, and an LR or SC to it stopped the simulation
(`a_lr_sc_reservable`). Loud beats silently wrong.

## 3. Two ways to keep a reservation honest

- **Make the core see every write: coherence.** A core with a coherent cache reserves the
  cache line; another core's write must first take the line away, which ends the
  reservation. Rocket and BOOM work this way. It needs a coherence protocol, which Mig6
  does not have on purpose: its shared memory is never cached, so it has one copy of
  everything and nothing to keep coherent.
- **Keep the reservation where every write passes: a monitor at the memory.** AXI calls
  this an exclusive access: an exclusive read (ARLOCK) sets a reservation in a monitor at
  the slave or the interconnect, an exclusive write (AWLOCK) is done only if it holds, and
  its response says which (EXOKAY: done; OKAY: not done). Arm's chips keep global
  exclusive monitors at memory controllers; PULP's `axi_riscv_lrsc` puts one in front of a
  memory.

Mig6 took the second. The place that sees every write to the shared memory, and knows who
sent it, is the shared memory's network interface: every PE's requests arrive there, one at
a time, each with its source PE.

## 4. The monitor

One reservation per PE: a valid bit and a word address. Four rules:

- **An LR reserves.** It goes to the memory as an ordinary read; when the memory takes it,
  its PE's reservation becomes valid for its word. A second LR replaces the first.
- **Any write ends every reservation of its word.** A write, an atomic or a successful SC,
  from any PE, the writer's own reservation too. (Ending the writer's own is allowed: a
  well-formed LR/SC loop has no store between the LR and the SC.)
- **An SC asks the monitor.** If its PE's reservation is valid and for the same word, it
  goes to the memory as an ordinary write. If not, it goes nowhere.
- **Either way the SC ends its PE's reservation** and is answered with its status.

```
  PE 0: LR X  --> monitor: resv[0] = X ---> memory read
  PE 1: SW X  --> monitor: ends resv[*] of X --> memory write
  PE 0: SC X  --> monitor: resv[0] gone --> fail, write nothing
           <-- answer: status 1
```

One detail kept me honest about order. Answers on Mig6's network carry no IDs: a PE's
answers come back in the order of its requests. Reads and atomics are answered by the
memory; an SC's status is made by the monitor itself. If the monitor answered an SC while
an earlier read was still in the memory, the SC's answer could overtake the read's. So an
SC is decided only when no answer is pending in the memory, and its answer joins the queue
behind the ones before it. The block in front of the memory that does the atomics waits the
same way before an atomic. It costs an SC a few clocks now and then; the alternative, tags on
every answer, costs every request.

## 5. On the way there, the channel had to learn two words

The monitor is a few dozen lines. Getting LR and SC from the core to it was the bigger job,
because the library's request channel, used by every cache, multiplexer and memory block,
could not say what was needed.

- **"Exclusive."** The channel got `req_excl`: an exclusive read is an LR, an exclusive
  write an SC, as AXI's ARLOCK and AWLOCK. Not new codes in the atomic-operation field: that
  field holds AXI's AWATOP values exactly, and LR/SC are not among them.
- **"I want an answer."** This was the surprise. The channel's rule had been "a write gets
  no answer": `we = 1` meant both "a write" and "no answer". An AMO already bent the rule
  (it writes but is answered, so it travelled as a read); an SC breaks it, since the core
  must learn whether it succeeded. The channel got `req_rsp`, "this request will be
  answered", and every block that keeps answers in order now counts `req_rsp` instead of
  `!we`.

Real buses answer every write (AXI's B channel, TileLink's AccessAck); posted writes were a
simplification that held while stores reached one memory on one path. Changing it did not
mean changing every block: only the ones between a requester and the block that answers,
which count and route answers. The targets that never answer a write, the RAM models and
the devices, stayed as they were; a requester just never sends them a write that wants an
answer.

The caches on the way treat an exclusive request like an atomic: never a hit, never merged
into a line, sent to memory as asked, the line dropped if it was there. An SC that fails at
the memory must not have put its bytes into a cached copy. A plain store that asks for an
answer is not supported yet, and says so with an assertion: when fences need acknowledged
stores, they will be merged and acknowledged, as CVA6's write-through cache does, inside one
block.

## 6. On the network: two opcodes and an acknowledgement

A request's head on Mig6's network is 48 bits, exactly full: the route, the opcode, the
source, size, address. There was no bit left for an exclusive flag, but the 3-bit opcode had
room:

```
  REQ_LR  head alone, as a READ;  answer DATA, the word
  REQ_SC  head + WRITE body;      answer ACK, the status

  ACK  | dest 4 | op 3 | status 32 |
       status: 0 success, 1 failure
```

The status is what the SC instruction writes to its destination register, so the core can
take the answer as it comes. DATA stays "here is what you read"; ACK is "your write is done,
and here is how it went", as AXI's R and B channels split them.

## 7. How it was tested

Mig6's network tests replace the cores with stand-ins: small testbench requesters that send
random requests and check every answer.

- **One stand-in, its own window.** LRs and SCs mixed with reads, writes and atomics in a
  window no one else touches. The stand-in keeps a model of its reservation, kept as the
  monitor keeps it, and predicts every SC's status; most SCs go to the reserved word, so
  both outcomes happen hundreds of times.
- **Four stand-ins, one word.** Every PE increments one shared word 30 times with LR/SC
  loops, retrying until its SC succeeds. In one run: 120 increments, 50 SCs failed under
  contention, and the word ended at exactly 120.
- **The check that the check works.** In a scratch copy, the monitor was made to end only
  the writer's own reservation, the bug of section 2 moved into the monitor. No SC failed,
  and the word ended at 79: 41 increments lost, caught.

## 8. What is left

The cores do not send LR and SC to the shared memory yet; they still stop at the assertion.
The next step: the core sends LR/SC as exclusive requests when the address is in a region
that is reservable but not cached, the shared region becomes reservable, and a program on
the four cores does compare-and-swap with `__atomic_compare_exchange`, checked against the
same count done with `amoadd`.

The knowledge base has the reasoning behind each step, with the options not taken:
[the monitor](../kb/rtl/design/mig6/far_lr_sc.yaml),
[answered writes](../kb/rtl/lib/block/answered_writes.yaml),
[exclusive requests in the caches](../kb/rtl/lib/block/cache/exclusive.yaml).
The code: `rtl/design/mig6/mig6_mem_net_if.sv` (the monitor), `mig6_noc_pkg.sv` (the
messages), `test/design/mig6/tb/tb_mig6_noc.sv` (the four-PE test).
