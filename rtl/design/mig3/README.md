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
Two things are not done yet:

- After a miss on the first word of a line, fetch asks for the second word in the clock the
  line comes, at the place the refill writes: the cache replays it (a clock). That doubles
  the cost of a sequential miss and halves the gain the model predicted for fetch (fetch
  waits x0.40 instead of x0.20 in Dhrystone). Keeping the line in fetch would remove it.
- The longest path became 6.8 ns (was 6.1; 249 926 um2, +1.9 %): the word of the line is
  selected after the way that hits, so the late hit goes through one more multiplexer on
  its way to decode.

## Notes

- The code keeps its `@kb:` tags to Mig2's kb records (`kb/rtl/design/mig2/`): those decisions
  were made in Mig2, and they still explain the copied code. Decisions made in Mig3 get records
  in `kb/rtl/design/mig3/`.
- Tests and options are Mig2's with the name changed: `design_mig3_*`,
  `DARK_CIRCUIT_MIG3_TRACE`, `DARK_CIRCUIT_MIG3_KANATA`, `make mig3_synth`.
