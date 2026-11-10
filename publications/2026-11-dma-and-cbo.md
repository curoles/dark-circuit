# The DMA wrote it, the cache kept the old copy: cbo.inval on my RISC-V core

*November 2026. Igor Lesik. Code: [dark-circuit](../README.md), an open library of hardware
blocks and the small RISC-V cores built from them.*

A DMA engine copies data into memory while the core does something else. When it is done,
the core reads the buffer and expects the new data. If the core had read that buffer
before, a copy of it may still be in the data cache, and the DMA wrote memory, not the
cache. The core then reads its old copy, and nothing tells it so.

There are two ways out. Hardware can keep the cache coherent with the DMA's writes: the
cache sees every write the DMA makes and drops or updates its copy. Or software tells the
cache, before it reads the buffer, to drop the lines that hold it. RISC-V has instructions
for the second way since 2021: Zicbom, with `cbo.inval`, `cbo.clean` and `cbo.flush`.

I added them to Mig3, my 5-stage in-order RISC-V core (RV32IM with Zbb and A), which now
has a DMA next to it. This note shows the stale copy happening in simulation, how a CBO
travels from the decoder to the memory, and how a testbench can check a load whose right
answer is "the old value, for now".

## 1. A stale line, in a trace

The test program stores 16 words into a buffer: 0x01d00000, 0x01d00001, and so on. Mig3's
data cache writes through and does not allocate on stores, so memory has them and the cache
does not. Then the program loads them: these loads miss, and the cache fills its lines. Then
the DMA copies 16 other words over the buffer: 0x0ee00000 and up. Then the program loads
the buffer again.

Here is the first word of the buffer, at address 0x4e8, as the testbench's trace shows its
loads:

```
cycle  load of 0x4e8
  316  01d00000  a miss: the line fills
  598  01d00000  after the DMA: stale
  827  01d00000  after cbo.clean: stale
 1043  0ee00000  after cbo.flush: new
```

At cycle 598 memory has held 0x0ee00000 for a while; the load still returns 0x01d00000
from the cache. All 16 words were stale. `cbo.clean` changed nothing, which is right for a
write-through cache (more on that below). After `cbo.flush` over the first half of the
buffer and `cbo.inval` over the second, every load missed and returned the DMA's data.

## 2. Coherent in hardware, or told by software

- **Hardware I/O coherence.** The DMA's writes go through a port where the caches see them:
  each write looks up the cache's tags and drops (or updates) the line. x86 does this for
  ordinary DMA, which is why x86 drivers rarely think about it. Arm systems do it when the device
  sits on a coherent port (ACE-Lite, the ACP). It costs a lookup port on the cache's tags
  and the wires from every DMA to every cache.
- **Software maintenance.** The cache is told, by instructions, which lines to drop or
  write back. Arm has `DC IVAC`, `DC CVAC` and `DC CIVAC` (invalidate, clean, both, to the
  point of coherency). RISC-V has Zicbom. Linux's DMA API calls them for devices that are
  not coherent: mapping a buffer for a device to write ends with an invalidate before the
  CPU reads it. On RISC-V that is `cbo.inval` over the buffer (and, on chips older than
  Zicbom, T-Head's own instructions, through an erratum).

Mig3 has a 1 KiB write-through data cache with one port on its tags. A snooping port for
one DMA would double the tag reads for the sake of a test. And the next cores do not make
software maintenance go away: a later core with an L2 and coherent caches still has
devices that are not coherent, and still needs to push data to memory on purpose. So
Mig3 got the instructions, and the hardware path they need is the one later cores keep.

## 3. Zicbom in one page

- **Three instructions,** each with one register operand: `cbo.clean (rs1)`, `cbo.flush
  (rs1)`, `cbo.inval (rs1)`. No offset; rs1 may point at any byte of the block.
- **The block** is the cache block, its size a power of two that the platform tells software
  (in Linux's device tree, `riscv,cbom-block-size`). On Mig3 it is a data-cache line, 8
  bytes; real chips use 64.
- **clean** writes the block to memory if a cache holds it dirty, and keeps it.
- **inval** drops the block from the caches. In a write-back cache, stores that only the
  cache holds are lost, so an operating system can make `cbo.inval` trap or act as a flush
  for less privileged code (the CBIE field of menvcfg). Mig3 runs in machine mode only.
- **flush** is clean, then inval.
- **Never misaligned:** a block is named by any byte in it.

Their encoding shares the opcode of FENCE (MISC-MEM), with funct3 2 and the operation in
the immediate field: 0 inval, 1 clean, 2 flush, 4 zero (`cbo.zero`, the separate Zicboz).

## 4. A CBO is a store of no bytes

In Mig3 the decoder turns the three instructions into one kind: a store to the address in
rs1, with immediate 0, that reads no rs2, carrying its operation in a new field, `cmo`. The
load/store unit sends it like a store, with no byte strobes:

```systemverilog
assign cbo = store &&
    dec.mem.cmo != CMO_NONE;
assign misaligned =
    (load || store) && unaligned
    && !cbo;
// strobes: none for a CBO,
// else by funct3 and offset
assign dmem_req.cmo = dec.mem.cmo;
```

The store path already does everything a CBO needs: it looks the address up in the data
cache, sends a request to memory, holds the execute stage until the cache takes it, and keeps
the request in order with the loads behind it. What the core adds is a mux on the strobes,
one on the byte offset, and one term in the misaligned check. The check needs it because a
CBO's funct3 is a word access's: without `!cbo`, `cbo.inval` of an odd address would trap.

Two details came up while doing it:

- **The immediate.** The decoder picks the immediate by opcode, before the instruction is
  fully decoded (it is on the longest path). MISC-MEM's immediate is now 0: a CBO's address
  is rs1, and FENCE uses no immediate.
- **The offset.** The CBO goes out with byte offset 0: an uncached access must be aligned to
  its size, and a CBO says "word" in its funct3. The cache only needs the line.

In the retire trace a CBO has an address and no byte masks: it writes no byte.

The cost, measured with Yosys on the open sky130 cell library (the core with its caches):
292 um2 more, 0.09 % of the area. ABC's estimate of the longest path went from 5.5 to 5.7 ns,
but it is the same path as before, from rs1 in the execute stage, through the same 26 cells;
ABC sized two of its gates and a buffer smaller this time. None of the CBO logic is on it.

## 5. The operation travels down

The library's request channels already carried one extra field for atomics, `atop` (my note
*Atomics next to the memory*). The CBO got a second one beside it:

```systemverilog
typedef logic [1:0] cmo_t;
CMO_NONE  = 2'b00;
CMO_CLEAN = 2'b01;  // bit 0: clean
CMO_INVAL = 2'b10;  // bit 1: drop
CMO_FLUSH = 2'b11;
```

What each level does with it:

- **The data cache** looks the CBO up like a store. An inval or a flush that hits drops the
  line in the clock memory takes the request; in the clock the CBO is looked up, the cache
  takes no new request (one bubble), so nothing reads the line still valid. A clean drops
  nothing: a write-through cache has nothing dirty to write. Every CBO then goes on to
  memory as a store of the line with no strobes, with its `cmo`.
- **The arbiter** in front of the one memory (instruction and data caches share it) carries
  the field with the data cache's requests.
- **ReqMux,** where the core and the DMA meet, carries it to the block in front of the
  memory, and there it ends: the RAM holds no lines. When the next core gets an L2 there,
  the L2 acts on a field that already arrives.
- **A device** in the I/O region gets a CBO as a write of no bytes. Every device of the
  library writes its registers by their strobes, so nothing changes.

Carrying the operation down is what the big protocols do too. AMBA's ACE5-Lite and CHI have
CleanShared, CleanInvalid and MakeInvalid, which match clean, flush and inval, and pass them
from level to level until the point the platform says is far enough.

A CBO gets no answer. The core does not wait for it; the order is kept by the path: the data
cache takes nothing while an inval waits for memory, and a load behind it goes the same way,
later.

## 6. Checking a load whose right answer is the old value

My testbench checks every retired instruction against a model, and every load against the
memory: the bytes a load returns must be the memory's, with the stores still on their way
on top. The stale load of section 1 breaks that rule, on purpose. Three ways to live with it:

- **Turn the check off** for this test. The test then checks only itself.
- **Skip loads of words the DMA wrote,** until a CBO drops them. A wrong value that is
  neither old nor new would pass.
- **Allow the old value or the new one,** until a CBO drops it.

I took the third. The checker watches the DMA's writes where they enter ReqMux. For every
word the DMA writes, it keeps the word that was in memory before the DMA's first write to
it. A load of such a word may return that old word or the memory's. When a `cbo.inval` or
`cbo.flush` of the block retires, the checker forgets the old words of that block, and from
then on loads of them are checked against memory again, strictly. A `cbo.clean` does not end
anything: the old copy may stay.

This is exactly the contract software relies on: before the CBO, either value; after it,
the new one. It also catches a CBO that does not do its job. With the data cache made to
ignore inval and flush, the first load after the CBO returns the old word, and the checker
stops the run there.

Four deliberately broken versions, all caught:

- **the data cache never sees inval or flush:** the checker, on the first load after the CBO;
- **cbo.inval decoded as a clean:** the decoder's unit test, and the checker;
- **a CBO that writes bytes:** an assertion in the cache control (a CBO has no strobes);
- **a CBO that traps as misaligned:** the test invalidates through the last byte of each
  block, and the trap ends it.

## 7. The test program

The C program is short. It uses Mig3's DMA driver and a new one for the CBOs, built with
`-march=rv32i_zicbom` (gcc 12.2 knows Zicbom):

```c
for (i = 0; i < 16; i++) {
    buf[i] = old_word(i);
    src[i] = new_word(i);
}
stale();            // 16 old: lines fill
dma_run(...);       // src over buf
// wait for done, with a deadline
stale();            // 16 old: stale
cbo_clean_range(buf, 64, 8);
stale();            // 16 old: kept
cbo_flush_range(buf, 32, 8);
// cbo.inval by the last byte
// of each block of the 2nd half
stale();            // 0 old: new
```

`stale()` loads the 16 words and counts the old ones; a word that is neither old nor new
ends the test with an error. The compiler unrolled the last loop into four `cbo.inval`
instructions with addresses `buf + 39`, `buf + 47`, `buf + 55` and `buf + 63`: none of them
aligned, each naming its block.

## 8. What it leaves out

- **cbo.zero and the prefetches.** Zicboz (zero a block without reading it) and Zicbop (the
  prefetch hints) are not in Mig3. gcc 12.2 accepts Zicbop in -march but never emits a
  prefetch.
- **A write-back cache.** With Mig3's write-through cache, clean does nothing and an inval
  loses nothing. With a write-back cache, the clean before the DMA reads a buffer matters,
  and inval and flush differ.
- **An 8-byte block.** Mig3's lines are small, so a buffer needs many CBOs. Software must
  take the size from the platform (here `MIG3_CBO_BLOCK_SIZE`), never assume 64.
- **The checker's model** does not cover a store of the core to a word the DMA wrote,
  before the CBO; the test program does not do that.
- **No permission check.** Mig3 has one privilege mode and no physical memory protection, so
  a CBO never faults.

## 9. How it compares

- **x86:** DMA is coherent by snooping, so drivers need nothing. `clflush` and `clwb`
  exist, mostly to push data to persistent memory.
- **Arm:** coherent ports for devices that have them, `DC IVAC`, `DC CVAC` and `DC CIVAC`
  for the rest; Linux picks per device.
- **RISC-V before Zicbom:** vendor instructions (T-Head's) or no software way at all.
- **RISC-V with Zicbom:** the same three operations as Arm, by block, one register operand.
- **Mig3:** Zicbom on a write-through cache, carried down as a field next to `atop`, so the
  L2 of the next core can act on the same request.

The code is in the repository: the core's side in `rtl/design/mig3/mig3_decode.sv` and
`mig3_lsu.sv`, the cache's drop in `rtl/lib/block/cache/cache_control`, the driver in
`sw/riscv/drivers/cbo.h`, the test in `test/design/mig3/cbo_dma.c`, the checker's model in
`test/design/mig3/tb/tb_mig3_retire_check.sv`. The knowledge-base records behind this note
are `kb/rtl/lib/block/cache/cbo.yaml`, `kb/rtl/design/mig3/cbo.yaml` and
`kb/rtl/design/mig3/dma.yaml`.
