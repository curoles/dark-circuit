# Mig2: RISC-V CPU

Mig2 is where bigger changes of the Mig CPUs go first. It started as a copy of Mig1
(`rtl/design/mig1`) on 2026-10-19; Mig1 took over its code on 2026-10-23, 2026-10-24 and
2026-10-25. See Mig1's README for how it works: its pipeline, branch prediction in ID,
bubbles, pipeline view, tests, logs (here `DARK_CIRCUIT_MIG2_TRACE` and
`DARK_CIRCUIT_MIG2_KANATA`), benchmark and cycle ceilings, synthesis (`make mig2_synth`
here); this file describes what Mig2 changes from Mig1: a BTB in IF and two more
benchmarks (2026-10-26). Mig1 does not take the BTB: it stays the small core.

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

## Benchmarks

Besides Dhrystone (see Mig1's README), Mig2 runs qsort and towers of riscv-tests
(`benchmarks/`), with the same support (`sw/riscv/bench`), cmake option and label:

- qsort: quicksort of 2048 random numbers, data-dependent branches; one run (the sort is
  in place: a second run would sort sorted numbers);
- towers: Towers of Hanoi with 7 discs, recursive: calls and returns; 50 runs.

The exit status of a benchmark is its own check (`verify` of riscv-tests), so a benchmark
also tests the CPU. Each has a cycle ceiling.

| Benchmark | Instructions | Static guess: cycles | CPI | BTB: cycles | CPI | Fewer cycles |
|---|---|---|---|---|---|---|
| Dhrystone | 1 643 635 | 2 134 146 | 1.298 | 1 978 237 | 1.204 | 7.3 % |
| qsort | 134 800 | 182 700 | 1.355 | 160 151 | 1.188 | 12.3 % |
| towers | 252 245 | 273 674 | 1.085 | 267 871 | 1.062 | 2.1 % |

The short tests hardly change: they run their code once, and the BTB knows a branch only
after it was taken (own programs 710 → 709 cycles, riscv-tests rv32ui and rv32um the same,
rv32mi 2 718 → 2 706).

## Area and speed (sky130)

Mig2Core with the flow of Mig1's README (`make mig2_synth TECH=sky130`), 2026-10-26:

| Mig2Core | |
|---|---|
| Area | 185 460 µm² (0.185 mm²), 21 330 cells |
| Longest logic path (ABC estimate) | 5.6 ns, about 179 MHz |

| Change | Area (µm²) | Longest path (ns) |
|---|---|---|
| Static branch guess in ID, as Mig1 | 159 076 | 5.3 |
| BTB in IF | 185 009 | 6.7 |
| ID's check with AddCmp | 185 460 | 5.6 |

The BTB adds 16 % of area: 688 flops with the hold mux of each, the read trees, two tag
comparators. Its first longest path was ID's check: decode, the adder of pc + imm, a 30-bit
compare with the address of IF, then the redirect. AddCmp (`rtl/lib/block/add_cmp`)
compares a + b with c without a carry chain (carry save): 6.7 → 5.6 ns. Two more changes
were tried and dropped: the next pc without PrgCounter, so that the redirect selects last,
and a BTB update written one cycle later (14 cycles more on qsort); with both 5.5 ns, with
the second alone 5.7 ns. Differences of a tenth or two of a nanosecond are within the error
of an estimate without wires; real timing needs placement and routing.

Time of a run (cycles × longest path): Dhrystone 11.31 → 11.08 ms (2.1 % faster), qsort
0.968 → 0.897 ms (7.4 % faster), towers 1.450 → 1.500 ms (3.4 % slower). The cycles do not
depend on the technology, and a deeper pipeline, where a taken branch costs more bubbles,
gains more from the BTB.

Planned: a return stack for returns (4.3 % of the cycles of Dhrystone are return bubbles);
the GShare predictor of `rtl/lib/block/gshare_branch_predictor` (struct version, its table
in Sram1R1W) for the direction; a faster multiplier, Spike cosim (lockstep), a Zbb slice,
a single memory instead of two.
