# Mig2: RISC-V CPU

Mig2 is where bigger changes of the Mig CPUs go first. It started as a copy of Mig1
(`rtl/design/mig1`) on 2026-10-19; Mig1 took over its code on 2026-10-23, 2026-10-24 and
2026-10-25. See Mig1's README for how it works: its pipeline, branch prediction in ID,
bubbles, pipeline view, tests, logs (here `DARK_CIRCUIT_MIG2_TRACE` and
`DARK_CIRCUIT_MIG2_KANATA`), benchmark and cycle ceilings, synthesis (`make mig2_synth`
here); this file describes what Mig2 changes from Mig1: a BTB in IF and two more
benchmarks (2026-10-26), a return-address stack in ID and a division that skips the
leading zeros of the dividend (2026-10-27). Mig1 does not take them: it stays the small
core. Why the design is as it is, with the options rejected:
`kb/rtl/design/mig2/`.

Simulation: Mig2 tests run on the main simulator of the build (cmake option
DARK_CIRCUIT_MAIN_SIMULATOR, by default Verilator when it is installed). Mig2 is tested
with Verilator; only Verilator is guaranteed to work.

## BTB in IF

Mig2Fetch has a branch target buffer (BranchTargetBuffer, `rtl/lib/block/branch_target_buffer`):
16 entries, direct-mapped, each with valid, tag, target and a 2-bit counter
(BranchCounterPkg). IF looks up the pc it requests; a hit whose counter says taken sends
fetch to the target in the same cycle, so a taken branch or JAL that the BTB knows costs no
bubble (from ID it costs one: `pred_taken`, `dir_jump`). What the BTB said (`btb_pred_t`:
hit, taken, counter) goes with the instruction through ID to EX.

- ID checks it (Mig2Control). A hit fits when the instruction is a branch or a JAL and
  fetch went where it says: pc + imm, the address IF requests now (AddCmp, see Area and
  speed); a JAL must be taken. ID trusts a hit that fits, also its direction: no static
  guess on top. A hit that does not fit (two pcs share an entry) is corrected as if the BTB
  had missed, one bubble (`BUBBLE_BTB_FIX`), and its entry is cleared. Without a hit, ID
  works as in Mig1: JAL from ID, the static guess for branches.
- EX updates the BTB with every conditional branch and JAL that completes (not one that
  traps), with the hit and counter it carried: no second read of the table. A taken miss
  gets an entry, weakly taken; a not taken miss gets none. EX corrects a wrong direction as
  before, two bubbles (`cond_branch`); `id_ex_t.redirected` now means that fetch went to
  the target, from IF or from ID.
- Size, in `cfg/mig2_config.yaml`: `btb_index_width` 4 (16 entries), `btb_tag_width` 10.
  Index and tag cover the word address of the 64 KiB imem, so no two pcs share an entry and
  ID never corrects the BTB; TbMig2BubbleCheck fails a run with a `btb_fix` bubble while
  that holds. With a shorter tag the corrections happen: a one-time run with a 2-bit tag
  passed every test, with 66 946 of them.
- JALR (returns, indirect jumps) does not go into the BTB.

`test/design/mig2/btb_if.S` runs the corners: loops and their exits, calls, branches taken
every time and every other time, two branches sharing an entry, a predicted branch waiting
in ID (load-use, division), predicted branches back to back, a loop of two instructions, a
predicted branch on the wrong path, and a branch to a misaligned target that traps twice and
then is not taken (it must not get an entry).

Before the BTB was built, a model of it in Python ran over the retire traces of the
benchmarks: 4, 8 and 16 entries, counters starting weakly or strongly taken, the static
guess on top of a not taken hit or not. Dhrystone alone gains almost as much with 4 entries
as with 16 (7.0 % against 7.3 % fewer cycles), but qsort and towers need 16; the start of
the counter hardly matters; the static guess on top makes qsort slower. Mig2 runs exactly
the cycles the model predicted.

## Return-address stack in ID

A return (JALR with rs1 x1 or x5, rd not rs1) goes back to the last call that has not
returned yet. Mig2Core has a return-address stack of 8 entries (ReturnAddressStack, a
Stack with OVERWRITE: when calls nest deeper, the oldest addresses go); Mig2Control pushes
the address after a call (JAL or JALR with rd x1 or x5) and pops for a return, both for a
swap (a coroutine), only when the instruction leaves ID (id_moves). ID sends a return to
the top of the stack: one bubble (`BUBBLE_PRED_RET`) instead of two. The prediction goes
with the return to EX (`id_ex_t.ras_target`); EX redirects when the real target differs
(`BUBBLE_RET`, two bubbles as before).

- No repair: an instruction that leaves ID is on the correct path and leaves once (the
  redirect of the only older instruction that can still redirect, in EX, comes in the same
  clock and stops it), so the stack only sees calls and returns that execute
  (`a_id_moves_ex` checks that an instruction that leaves ID reaches EX).
- The stack is outside Mig2Control, like the BTB: Control sends its commands (`ras_ctrl`)
  and gets its top (`id_ras_top`).
- Size, in `cfg/mig2_config.yaml`: `ras_addr_width` 3 (8 entries). A trace model chose
  it: with 8 every return of Dhrystone and towers is predicted right; towers nests 9 deep,
  with 4 entries 92.6 %.

`test/design/mig2/ras_id.S` runs the corners: recursion 12 deep (the stack wraps), an
empty function, returns waiting in ID (load-use, division), an indirect call, a return to
a changed ra (predicted wrong), a call on the wrong path and calls waiting in ID inside a
function (each must push once), a swap whose popped address must be gone, calls in a trap
handler.

## Division with early start

Mig2MulDiv divides with `Int32Div #(.EARLY_START(1))`: its Divider takes one step per
significant bit of the dividend's magnitude instead of 32 (at least one; all 32 for a
divisor of 0, which fits every step). A leading zero of the dividend would shift 0 into the
partial remainder, and a divisor that is not 0 never fits 0: the step would only make a
quotient bit 0. A division holds EX 2 + steps cycles: 34 for a 32-bit dividend, 6 for
9 / 7. The leading zeros are counted (PriorityEncoder) and shifted out (BarrelShifter) in
the start cycle, in EX, not in ID, where the operand comes through the forwarding mux.
`test/design/mig2/muldiv.S` checks the cycles of a 32-bit and of a 4-bit division.

## Benchmarks

Besides Dhrystone (see Mig1's README), Mig2 runs qsort and towers of riscv-tests
(`benchmarks/`), with the same support (`sw/riscv/bench`), cmake option and label:

- qsort: quicksort of 2048 random numbers, data-dependent branches; one run (the sort is
  in place: a second run would sort sorted numbers);
- towers: Towers of Hanoi with 7 discs, recursive: calls and returns; 50 runs.

The exit status of a benchmark is its own check (`verify` of riscv-tests), so a benchmark
also tests the CPU. Each has a cycle ceiling per compiler version (see Mig1's README, Cycle
ceilings). The cycles below were measured with gcc 10.2.0; gcc 12.2.0 compiles other code
(Dhrystone 4.2 % more cycles, qsort 2 cycles more, towers 12.3 % fewer).

| Benchmark | Instructions | Static guess: cycles | CPI | BTB: cycles | CPI | + return stack: cycles | CPI | + early division: cycles | CPI |
|---|---|---|---|---|---|---|---|---|---|
| Dhrystone | 1 643 635 | 2 134 146 | 1.298 | 1 978 237 | 1.204 | 1 932 864 | 1.176 | 1 848 768 | 1.125 |
| qsort | 134 800 | 182 700 | 1.355 | 160 151 | 1.188 | 160 147 | 1.188 | 160 147 | 1.188 |
| towers | 252 245 | 273 674 | 1.085 | 267 871 | 1.062 | 264 471 | 1.048 | 264 471 | 1.048 |

The BTB saves 7.3 %, 12.3 % and 2.1 % of the cycles, the return stack 2.3 % and 1.3 % more
(qsort hardly calls). The short tests hardly change: they run their code once, and the BTB
knows a branch only after it was taken (with the BTB: own programs 710 → 709 cycles,
riscv-tests rv32ui and rv32um the same, rv32mi 2 718 → 2 706). The early division saves
4.4 % of Dhrystone (3 000 of its 3 012 divisions are 9 / 7: 4 steps instead of 32); qsort
and towers do not divide; rv32um div and rem 457 → 349 cycles, divu and remu 458 → 404 and
457 → 403.

## Area and speed (sky130)

Mig2Core with the flow of Mig1's README (`make mig2_synth TECH=sky130`), 2026-10-27:

| Mig2Core | |
|---|---|
| Area | 199 474 µm² (0.199 mm²), 22 353 cells |
| Longest logic path (ABC estimate) | 5.7 ns, about 176 MHz |

| Change | Area (µm²) | Longest path (ns) |
|---|---|---|
| Static branch guess in ID, as Mig1 | 159 076 | 5.3 |
| BTB in IF | 185 009 | 6.7 |
| ID's check with AddCmp | 185 460 | 5.6 |
| Return-address stack in ID | 194 763 | 5.9 |
| ID's target: pc + imm into the last mux | 196 308 | 5.7 |
| Division with early start | 199 474 | 5.7 |

The BTB adds 16 % of area: 688 flops with the hold mux of each, the read trees, two tag
comparators. Its first longest path was ID's check: decode, the adder of pc + imm, a 30-bit
compare with the address of IF, then the redirect. AddCmp (`rtl/lib/block/add_cmp`)
compares a + b with c without a carry chain (carry save): 6.7 → 5.6 ns. Two more changes
were tried and dropped: the next pc without PrgCounter, so that the redirect selects last,
and a BTB update written one cycle later (14 cycles more on qsort); with both 5.5 ns, with
the second alone 5.7 ns. Differences of a tenth or two of a nanosecond are within the error
of an estimate without wires; real timing needs placement and routing.

Time of a run (cycles × longest path) with the BTB: Dhrystone 11.31 → 11.08 ms (2.1 %
faster), qsort 0.968 → 0.897 ms (7.4 % faster), towers 1.450 → 1.500 ms (3.4 % slower).
The return stack added 5.8 % of area (240 flops with their hold muxes, the read mux, the
prediction carried to EX, its comparator); its first longest path was ID's target, where
pc + imm went through two muxes (5.9 ns); with pc + imm in the last mux 5.7 ns, the
redirect from EX is the longest path again. With it: Dhrystone 11.02 ms (0.5 % faster),
towers 1.508 ms (0.5 % slower). The cycles do not depend on the technology, and a deeper
pipeline, where taken branches and returns cost more bubbles, gains more from both.
The early division added 1.6 % of area (3 166 µm², 358 cells: the priority encoder, the
32-bit barrel shifter, the step count and its muxes); the longest path stays 5.7 ns.
Dhrystone 11.02 → 10.54 ms (4.4 % faster); qsort and towers do not divide.

Not planned for now: the GShare predictor of `rtl/lib/block/gshare_branch_predictor`. A
trace model on top of the BTB and the return stack gives at most 1.9 % of Dhrystone
(perfect directions would give 2.3 %), nothing on qsort (its branches compare random
numbers) and 1.2 % on towers, for a table of flops (`kb/rtl/design/mig2/no_gshare.yaml`).

Planned: a faster multiplier, Spike cosim (lockstep), a Zbb slice, a single memory instead
of two.
