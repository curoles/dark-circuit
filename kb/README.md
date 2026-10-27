# Knowledge base

Code says what the design does; `kb/` keeps why: the decisions with the options that were
rejected, the invariants other code relies on, measurements, and attempts that were dropped.
A record is a small YAML file; a comment in the code points to it, the record points to the
code, and `make kb` checks that both still exist.

## Where records are

The paths of `kb/` mirror the repository: a record about `rtl/design/mig2` is in
`kb/rtl/design/mig2/`, one about the tests of Mig2 in `kb/test/design/mig2/`. The id of a
record is its path in `kb/` without `.yaml`: `rtl/design/mig2/btb_in_if`. Every directory of
`kb/` mirrors a directory of the repository (`make kb` checks it, so knowledge is not left
behind when code moves).

## In the code

A comment with `@kb:` and the id, at the code the record explains (above it, on its own
line), in any file:

```systemverilog
    // @kb: rtl/design/mig2/id_moves_correct_path
    assign id_moves = id_fetch.valid && !ex_stall && !id_hazard && !flush_id;
```

Before changing code with an `@kb:` tag, read its record: it says why the code is as it is
and what was tried before. Do not delete or move tagged code, or the tag, without deciding
what happens to the record: update it and its anchors, move it with the code, or, when the
decision is undone, turn it into a `dropped` record that says why. Never delete a record
silently: the knowledge would be lost with it.

## Records

A record is a YAML mapping. Every record has `type`, `title` (one line) and `date` (when it
was decided or measured, YYYY-MM-DD). Each type has its own fields:

| Type | Required | Optional |
|---|---|---|
| `decision` | `question`, `decision`, `why` | `rejected`: list of `choice`, `why_not` |
| `invariant` | `statement`, `why` | `checked_by`: anchors of the assertions or tests that check it |
| `measurement` | `what`, `result`, `how` (to reproduce) | `guarded_by`: anchors of the tests that keep it |
| `dropped` | `tried`, `result`, `why_dropped` | |

Every type may have `evidence` (text: numbers, where they come from), `code` (anchors) and
`relies_on` (ids of records this one builds on). No other fields.

An anchor is a path from the repository root, `rtl/design/mig2/mig2_fetch.sv`, or a path and
a name in that file, `rtl/design/mig2/mig2_control.sv#id_moves`: the name must be in the
file as a whole word (a signal, an instance, a module, an assertion, a CMake function).

```yaml
type: invariant
title: An instruction that leaves ID is on the correct path and completes
date: 2026-10-26
statement: >
  When id_moves=1 the instruction in ID goes to EX at the rising edge, ...
why: >
  The commit point is EX: ...
code:
  - rtl/design/mig2/mig2_control.sv#id_moves
```

## Checking

`make kb` (`tools/kb_check.py`) checks every record (YAML, type, fields), every anchor (the
file exists, the name is in it), every `relies_on` (the record exists), every `@kb:` in the
repository (the record exists) and the mirror of the directories; it lists records no code
points to. Run it after a change that adds records or moves, renames or deletes code with an
`@kb:` tag. It is not a test of the build: it reads text files, no simulator.

Write a record when a chunk decides something that the code alone does not explain, when an
invariant is relied on by other code, or when an attempt is dropped (so that it is not tried
again for the same reason). Not a record per signal: comments explain the code itself.
