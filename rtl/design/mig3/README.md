# Mig3

Mig3 is a copy of Mig2 made on 2026-11-04: the same 5-stage RV32IM_Zicsr_Zicntr core with Zbb,
branch prediction (BTB in IF, return-address stack and redirect in ID), instruction and data
caches in front of one memory, and the same tests. Mig2's README describes all of it; this one
describes only what Mig3 changes.

Mig3 is where floating point goes (the roadmap: Mig2 without FP, Mig3 with it), and with it the
first number formats of the AI direction later.

## What Mig3 changes

Nothing yet: every program runs in the same cycles as on Mig2.

## Notes

- The code keeps its `@kb:` tags to Mig2's kb records (`kb/rtl/design/mig2/`): those decisions
  were made in Mig2, and they still explain the copied code. Decisions made in Mig3 get records
  in `kb/rtl/design/mig3/`.
- Tests and options are Mig2's with the name changed: `design_mig3_*`,
  `DARK_CIRCUIT_MIG3_TRACE`, `DARK_CIRCUIT_MIG3_KANATA`, `make mig3_synth`.
