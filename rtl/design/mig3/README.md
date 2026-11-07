# Mig3

Mig3 is a copy of Mig2 made on 2026-11-04: the same 5-stage RV32IM_Zicsr_Zicntr core with Zbb,
branch prediction (BTB in IF, return-address stack and redirect in ID), instruction and data
caches in front of one memory, and the same tests. Mig2's README describes all of it; this one
describes only what Mig3 changes.

Mig3 is where floating point goes (the roadmap: Mig2 without FP, Mig3 with it), and with it the
first number formats of the AI direction later.

## What Mig3 changes

### Cache lines of two words

Both caches hold lines of two words (8 bytes, `cache_line_words` in `cfg/mig3_config.yaml`),
64 sets a way, so 1 KiB each; the one memory moves a line a request. The pipeline's side
stays one word: Mig3Caches gives a fetch or a load its word of the line, and puts a store's
word and strobes into its place in the line. Both caches have the same line size so that a
shared L2 and coherence later deal with one size. Why, with the model that predicted it:
`kb/rtl/design/mig3/cache_lines.yaml`.

| Benchmark (gcc 12.2.0, cached) | One-word lines | Two-word lines | Change |
|---|---|---|---|
| Dhrystone | 2 598 076 | 2 195 494 | -15.5 % |
| qsort | 178 456 | 168 216 | -5.7 % |
| towers | 317 317 | 242 993 | -23.4 % |

Uncached programs, among them the tests that count cycles, keep their cycles exactly.
With two-word lines the longest path first became 6.8 ns (was 6.1): the word of the line
was selected after the way that hits, and the late hit went on through decode in the same
clock. After a miss on the first word of a line, fetch asked for the second
word in the clock the line came, at the place the refill writes, and the cache replayed it
(a clock): that doubled the cost of a sequential miss (fetch waits x0.40 in Dhrystone, the
model x0.20). The line kept in fetch removes it (below).

### A register stage before ID

Mig3Fetch puts a register between the I-cache's answer and ID: the slot that waits for
the word is IF2, and ID decodes a word from a flop, never the I-cache's answer of the same
clock. The longest path is 5.3 ns (189 MHz; 254 936 um2), now in EX. The price is a clock
more after every redirect (taken branch, jump, return, a correction of the BTB, a trap):
the target goes through both stages before ID. Fetch hands ID the address it requested
after each instruction (id_next_pc), which Mig3Control checks the BTB's prediction with:
IF is two instructions ahead of ID by then. Why: `kb/rtl/design/mig3/fetch_stage.yaml`.

| Benchmark (cached) | Two-word lines, 6.8 ns | With the register stage, 5.3 ns | Run time |
|---|---|---|---|
| Dhrystone | 2 195 494 | 2 305 787 (+5.0 %) | -18 % |
| qsort | 168 216 | 179 022 (+6.4 %) | -17 % |
| towers | 242 993 | 250 725 (+3.2 %) | -20 % |

Against Mig3 as copied (one-word lines, 6.1 ns): -23 %, -13 % and -31 % in run time. The
tests that count cycles and the benchmark ceilings (pipeline cycles) are measured again:
branch_id 171, btb_if 524, ras_id 462; Dhrystone 2 059 000, qsort 169 000, towers 239 000.

### Fetch keeps the line

The I-cache answers fetch with the whole line, and Mig3Fetch keeps the line of every
answer it uses. When the next instruction is in that line (or in the line arriving in this
clock), it goes into IF2 with its word at once, without a request to the I-cache: the
second word of a line is never replayed after a miss, and in straight code half the
requests are gone. Fetch selects the word, before ID's register, so no late path is added.
Uncached, every instruction is still a request: uncached programs and the tests that count
cycles keep their cycles exactly. Why: `kb/rtl/design/mig3/fetch_line.yaml`.

| Benchmark (cached) | Register stage | Kept line | Change |
|---|---|---|---|
| Dhrystone | 2 305 787 | 2 210 485 | -4.1 % |
| qsort | 179 022 | 178 972 | -0.0 % |
| towers | 250 725 | 244 818 | -2.4 % |

Dhrystone's I-cache bubbles go from 285 254 to 174 196; qsort fits in the I-cache and had
almost none. The cached tests run 4..26 % fewer cycles (rv32ui_add 986 -> 807): small
programs, mostly first misses. sky130: 5.4 ns, 258 623 um2 (the longest path still starts
at the ID/EX register in EX).

### A BTB of 64 entries

The BTB has 64 entries (was 16; `btb_index_width` in `cfg/mig3_config.yaml`). In
Dhrystone the 16 entries were too few: JALs the BTB did not know made ID redirect (2
bubbles each), and branches without an entry got the static guess of ID instead of their
counter. Why 64, and the sizes measured: `kb/rtl/design/mig3/btb_size.yaml`.

| Benchmark (cached) | 16 entries | 64 entries | Change |
|---|---|---|---|
| Dhrystone | 2 210 485 | 2 091 626 | -5.4 % |
| qsort | 178 972 | 177 596 | -0.8 % |
| towers | 244 818 | 244 437 | -0.2 % |

sky130: 5.2 ns, 331 045 um2 (+28 %: the BTB is flops). The ceilings are measured again:
btb_if 506; Dhrystone 1 956 000, qsort 168 000, towers 238 000.

### Atomics (A: Zalrsc and Zaamo)

Mig3 runs LR.W and SC.W, the load-reserved and store-conditional of the A extension
(its AMOs: below). Everything of them that is not a load or a store is
in one part, Mig3Atomic, in EX: the reservation of one word, which an LR takes and an SC,
a trap or MRET ends. A failing SC cancels its store in Mig3Lsu and writes 1 to rd, a
succeeding one 0; that result comes in MEM/WB, like a load's (forwarded from EX it made
the longest path 5.7 ns; so it stays 5.2). The test lrsc.S runs LR/SC in the corners of
the pipeline, and the retire check checks every SC against a reservation of its own.
Why: `kb/rtl/design/mig3/lr_sc.yaml`.

The AMOs (AMOADD.W ... AMOMAXU.W) are done in front of the memory, where every access
to it meets: AtomicUnit (`rtl/lib/block/atomic`) in Mig3Cpu, behind the caches. The core
sends an AMO as a word load with its operation (atop, AXI5's values; AMOAND sends ~rs2,
a clear); the D-cache never hits it and drops the line it hits; the old word comes back
as a load's and goes to rd. misa.A is 1. riscv-tests rv32ua pass; the retire check
computes every AMO's new word and checks the memory's write of it. Why:
`kb/rtl/design/mig3/amo.yaml`.

### Interrupts

Mig3 takes the machine external interrupt: one input, meip, the level an interrupt
controller holds until the interrupt is claimed (a PLIC in Mig3Cpu later; the testbench
now). mie.MEIE enables it, mip.MEIP shows it, mstatus.MIE is the global enable. It is
taken on the instruction in EX in the first cycle that instruction acts: it does nothing,
traps with mcause 0x8000000b, and runs again after MRET. The testbench raises meip at
random times (+irq_random) and drops it when the handler claims with a store to
irq_claim. irq.S places interrupts on chosen instructions; irq_random.S checks that
interrupts at random places do not change what a program computes. WFI is a no-op. Why:
`kb/rtl/design/mig3/interrupts.yaml`.

## CoreMark

CoreMark (EEMBC) runs as three benchmark tests: its sources unchanged (fetched at
configure time), a port of this project in `sw/riscv/coremark` (ticks are clock cycles;
the exit status is the check of its CRCs), the standard performance run. The three
builds of the one source load the CPU differently. Why and how:
`kb/test/design/mig3/coremark.yaml`.

| Test (gcc 12.2.0) | Build | What it loads | CoreMark/MHz cached | uncached |
|---|---|---|---|---|
| coremark | -O2, rv32im | code as usually compiled; regression ceiling | 2.764 | 2.452 |
| coremark_tuned | flags of published RISC-V scores, rv32im_zbb | fetch: 38 KB of code for a 1 KiB I-cache; the score to compare | 3.445 | 2.963 |
| coremark_O0 | -O0, rv32im | loads and stores: every variable on the stack | 0.653 | 0.570 |

Cached, the biggest bubbles: coremark wrong guesses of branches (6.3 % of cycles) and
load-use (5.6 %); coremark_tuned wrong guesses (7.2 %), load-use (4.5 %) and the I-cache
(3.0 %); coremark_O0 load-use (22 %).

Simulated: a valid CoreMark score must run at least 10 s; these are not EEMBC-certified
scores. CoreMark is a trademark of EEMBC.

## Notes

- The code keeps its `@kb:` tags to Mig2's kb records (`kb/rtl/design/mig2/`): those decisions
  were made in Mig2, and they still explain the copied code. Decisions made in Mig3 get records
  in `kb/rtl/design/mig3/`.
- Tests and options are Mig2's with the name changed: `design_mig3_*`,
  `DARK_CIRCUIT_MIG3_TRACE`, `DARK_CIRCUIT_MIG3_KANATA`, `make mig3_synth`.
