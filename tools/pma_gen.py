#!/usr/bin/env python3
"""Generate a design's memory map (PMA-style: physical memory attributes) from its YAML.

Usage:
    pma_gen.py --root <repo> <design>_pma.yaml [--check]

The YAML (rtl/design/mig6/cfg/mig6_pma.yaml has the format in its header) lists regions,
each with a base, a size, a target and its attributes (cacheable, io, atomics, reservable),
optionally alias_of (the region is a second window onto that one: the same memory, its
address translated to the other's beyond the PE), and `generate`, a list of {template,
output} as for config_gen.py. This script checks the map (known keys, sizes powers of 2,
bases multiples of their sizes inside 32 bits, regions not overlapping, an io region not
cacheable, known targets; an alias names a region that is no alias, of the same size and
target), derives what the templates need and renders them with config_gen.py's
render_outputs: written only when changed, --check fails when an output is out of date.

The templates get `regions` (in the YAML's order) and `targets` (every target name, in the
order of TARGETS: their enum values). A region has name, base, size, desc, target, the four
attributes (booleans); derived: NAME (upper case), TARGET (upper case), addr_width (log2 of
size: the low address bits inside it), top (address bits 31:addr_width of base, the part a
decode compares), bits (the attributes as SystemVerilog bits, "1'b1, 1'b0, ...", in the
order of ATTRIBUTES), alias (the region it aliases, its derived parts; None when not an
alias).
"""
import argparse
import os
import sys

import yaml

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from config_gen import render_outputs  # noqa: E402

ADDR_WIDTH = 32
TARGETS = ("local", "net", "devices")
ATTRIBUTES = ("cacheable", "io", "atomics", "reservable")
REGION_KEYS = {"name", "base", "size", "desc", "target", *ATTRIBUTES}
OPTIONAL_KEYS = {"alias_of"}


def fail(msg):
    print(f"pma_gen: {msg}", file=sys.stderr)
    sys.exit(1)


def region_of(r):
    """A region of the YAML, checked, with its derived parts."""
    name = r.get("name")
    extra = set(r) - REGION_KEYS - OPTIONAL_KEYS
    if extra:
        fail(f"{name}: unknown {', '.join(sorted(map(str, extra)))} (a ': ' or a comma in a "
             f"text? quote it)")
    missing = REGION_KEYS - set(r)
    if missing:
        fail(f"{name}: missing {', '.join(sorted(missing))}")
    base, size = r["base"], r["size"]
    if not isinstance(size, int) or size <= 0 or size & (size - 1) or size >= 1 << ADDR_WIDTH:
        fail(f"{name}: size {size} is not a power of 2 below 2^{ADDR_WIDTH}")
    if not isinstance(base, int) or base % size or base + size > 1 << ADDR_WIDTH:
        fail(f"{name}: base {base:#x} is not a multiple of its size {size:#x} in "
             f"{ADDR_WIDTH} bits")
    for a in ATTRIBUTES:
        if not isinstance(r[a], bool):
            fail(f"{name}: {a} must be yes or no")
    if r["target"] not in TARGETS:
        fail(f"{name}: target {r['target']} is not one of {TARGETS}")
    if r["io"] and r["cacheable"]:
        fail(f"{name}: an io region can not be cacheable (side effects)")
    addr_width = size.bit_length() - 1
    bits = ", ".join(f"1'b{int(r[a])}" for a in ATTRIBUTES)
    return {**r, "NAME": name.upper(), "TARGET": r["target"].upper(),
            "addr_width": addr_width, "top": base >> addr_width, "bits": bits,
            "alias_of": r.get("alias_of"), "alias": None}


def model(regions):
    out, names = [], set()
    for r in regions:
        m = region_of(r)
        if m["name"] in names:
            fail(f"{m['name']}: described twice")
        names.add(m["name"])
        for o in out:
            if m["base"] < o["base"] + o["size"] and o["base"] < m["base"] + m["size"]:
                fail(f"{m['name']}: overlaps {o['name']}")
        out.append(m)
    # An alias: a second window onto a region (the same memory), offset for offset.
    by_name = {m["name"]: m for m in out}
    for m in out:
        if m["alias_of"] is None:
            continue
        a = by_name.get(m["alias_of"])
        if a is None:
            fail(f"{m['name']}: alias_of {m['alias_of']} is no region")
        if a["alias_of"] is not None:
            fail(f"{m['name']}: alias_of {a['name']}, itself an alias")
        if a["size"] != m["size"] or a["target"] != m["target"]:
            fail(f"{m['name']}: alias_of {a['name']} of another size or target")
        m["alias"] = a
    return {"regions": out, "targets": [{"name": t, "NAME": t.upper()} for t in TARGETS]}


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("config", help="the design's PMA YAML")
    parser.add_argument("--root", required=True, help="repository root, outputs are relative to it")
    parser.add_argument("--check", action="store_true",
                        help="do not write, fail when outputs are missing or differ")
    args = parser.parse_args()

    try:
        with open(args.config) as f:
            config = yaml.safe_load(f)
    except yaml.YAMLError as e:
        fail(f"{args.config} is not valid YAML (a ': ' in a text? quote it):\n{e}")
    generate = config.pop("generate", [])
    return render_outputs(model(config["regions"]), generate, args.config, args.root,
                          args.check, tool="pma_gen", trim=True)


if __name__ == "__main__":
    sys.exit(main())
