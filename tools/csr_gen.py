#!/usr/bin/env python3
"""Generate a design's core CSR package and header from its CSR YAML (AGENTS.md, Terminology).

Usage:
    csr_gen.py --root <repo> <design>_csr.yaml [--check]

The YAML (rtl/design/mig6/cfg/mig6_csr.yaml has the format in its header) lists groups of
CSRs, each CSR with its fields or as a view of another, and `generate`, a list of
{template, output} as for config_gen.py. This script checks the description (unique names
and addresses, fields inside 32 bits and not overlapping, known access kinds, reset for a
stored field and from for a live one, no rw field at a read-only address, views of CSRs and
fields that exist), derives what the templates need, and renders them with config_gen.py's
render_outputs: written only when changed, --check fails when an output is out of date.

The templates get `groups` and `csrs` (every CSR in the YAML's order), `state` (the CSRs a
design keeps or wires: fields that are not all constant) and `views`. A CSR has name,
addr, desc, group and either view (of, fields) or fields; derived: NAME (upper case),
valid (the bits of its fields), sw_write (its rw fields), const (fields ro and none: always
their reset), reset (stored and constant fields after reset), all_const, members (the
struct from bit 31 down: fields and the zero gaps, each {name, width, field}). A field:
name, NAME, hi, lo, width, mask, sw, hw, reset (None when live), src (from, None when
stored). A view adds target (the CSR it shows) and, for some fields, pack (them from bit 0,
each {field, at}); its valid and sw_write are those bits seen from the view.
"""
import argparse
import os
import sys

import yaml

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from config_gen import render_outputs  # noqa: E402

WIDTH = 32
SW = ("ro", "rw")
HW = ("none", "write", "live")
CSR_KEYS = {"name", "addr", "desc", "fields", "view"}
FIELD_KEYS = {"name", "bits", "reset", "from", "sw", "hw"}
VIEW_KEYS = {"of", "fields"}


def known_keys(where, item, keys):
    """A slip in the YAML (a comma in a one-line entry makes a key) is an error."""
    extra = set(item) - keys
    if extra:
        fail(f"{where}: unknown {', '.join(sorted(map(str, extra)))} (a comma in a one-line "
             f"entry? quote the text)")


def fail(msg):
    print(f"csr_gen: {msg}", file=sys.stderr)
    sys.exit(1)


def field_of(csr, f):
    """A field of the YAML with its bits, access and value checked; derived parts added."""
    where = f"{csr['name']}.{f.get('name')}"
    known_keys(where, f, FIELD_KEYS)
    bits = f["bits"]
    hi, lo = (bits, bits) if isinstance(bits, int) else bits
    if not 0 <= lo <= hi < WIDTH:
        fail(f"{where}: bits {bits} outside 0..{WIDTH - 1}")
    if f["sw"] not in SW or f["hw"] not in HW:
        fail(f"{where}: sw must be one of {SW}, hw one of {HW}")
    live = f["hw"] == "live"
    if live != ("from" in f) or live == ("reset" in f):
        fail(f"{where}: a live field has from, a stored field has reset")
    if live and f["sw"] == "rw":
        fail(f"{where}: a live field is read-only")
    width = hi - lo + 1
    reset = f.get("reset")
    if reset is not None and not 0 <= reset < (1 << width):
        fail(f"{where}: reset {reset} does not fit {width} bits")
    return {"name": f["name"], "NAME": f["name"].upper(), "hi": hi, "lo": lo, "width": width,
            "mask": ((1 << width) - 1) << lo, "sw": f["sw"], "hw": f["hw"], "reset": reset,
            "src": f.get("from")}


def members_of(fields):
    """The struct of a CSR, bit 31 first: its fields and zero_<hi>_<lo> for the gaps."""
    members, top = [], WIDTH - 1
    for f in sorted(fields, key=lambda f: -f["lo"]):
        if f["hi"] < top:
            members.append({"name": f"zero_{top}_{f['hi'] + 1}", "width": top - f["hi"],
                            "field": None})
        members.append({"name": f["name"], "width": f["width"], "field": f})
        top = f["lo"] - 1
    if top >= 0:
        members.append({"name": f"zero_{top}_0", "width": top + 1, "field": None})
    return members


READ_COLUMN = 39    # where csr_read's value expression starts in the generated package


def read_expr(m):
    """The SystemVerilog value of CSR m in csr_read, from csr_state_t s."""
    if m["view"]:
        if m["pack"]:
            parts = [f"s.{m['target']['name']}.{p['field']['name']}" for p in reversed(m["pack"])]
            return "32'({" + ", ".join(parts) + "})"
        return read_expr(m["target"])
    n, N = m["name"], m["NAME"]
    if not m["fields"]:
        return "'0"
    if m["all_const"]:
        return f"{N}_RESET"
    if m["const"] == 0:
        return f"s.{n} & {N}_VALID"
    return (f"(s.{n} & {N}_VALID & ~{N}_CONST)\n"
            f"{' ' * READ_COLUMN}| ({N}_RESET & {N}_CONST)")


def texts(m):
    """Text the templates print as it is: a title, field notes, declarations, the read."""
    m["title"] = f"{m['name']}: {m['desc']}"
    if m["view"]:
        what = m["view"]["of"]
        if m["pack"]:
            what += ": " + ", ".join(p["field"]["name"] for p in m["pack"]) + " from bit 0"
        m["title"] += f" (a view of {what})"
    for f in m["fields"]:
        bits = str(f["lo"]) if f["hi"] == f["lo"] else f"{f['hi']}:{f['lo']}"
        value = f"from {f['src']}" if f["src"] else f"reset {f['reset']}"
        f["note"] = f"{bits}, sw {f['sw']}, hw {f['hw']}, {value}"
    for mem in m["members"]:
        mem["decl"] = "logic" if mem["width"] == 1 else f"logic [{mem['width'] - 1}:0]"
    m["read"] = read_expr(m)
    # C: the type's name, Mig6Csr<Name>, and its bit-fields from bit 0 up (RISC-V's ABI
    # places bit-fields from the lowest bit); a view of some fields packs them from bit 0.
    m["Cname"] = m["name"][0].upper() + m["name"][1:]
    # C++: the width of the constants' names in the CSR's namespace (sw_write, <field>_shift).
    m["cxx_width"] = max([len("sw_write")] + [len(f["name"]) + len("_shift") for f in m["fields"]])
    if m["view"] and m["pack"]:
        top = sum(p["field"]["width"] for p in m["pack"])
        m["c_members"] = [{"name": p["field"]["name"], "width": p["field"]["width"]}
                          for p in m["pack"]] + [{"name": f"zero_31_{top}", "width": WIDTH - top}]
    else:
        m["c_members"] = [{"name": mem["name"], "width": mem["width"]}
                          for mem in reversed(m["members"])]


def model(groups):
    csrs, names, addrs = [], {}, {}
    for g in groups:
        for c in g["csrs"]:
            name, addr = c["name"], c["addr"]
            known_keys(name, c, CSR_KEYS)
            if "view" in c:
                known_keys(f"{name} view", c["view"], VIEW_KEYS)
            if name in names:
                fail(f"{name}: described twice")
            if addr in addrs:
                fail(f"{name}: address {addr:#05x} is also {addrs[addr]}'s")
            if not 0 <= addr < 4096:
                fail(f"{name}: address {addr:#x} is not 12 bits")
            if "view" in c and "fields" in c:
                fail(f"{name}: fields or view, not both")
            m = {"name": name, "NAME": name.upper(), "addr": addr, "desc": c.get("desc", ""),
                 "group": g["name"], "view": c.get("view"), "read_only": addr >> 10 == 3}
            fields = [field_of(c, f) for f in c.get("fields", [])]
            used = 0
            for f in fields:
                if used & f["mask"]:
                    fail(f"{name}.{f['name']}: overlaps another field")
                used |= f["mask"]
                if m["read_only"] and f["sw"] == "rw":
                    fail(f"{name}.{f['name']}: rw at a read-only address")
            m["fields"] = fields
            m["valid"] = used
            m["sw_write"] = sum(f["mask"] for f in fields if f["sw"] == "rw")
            m["const"] = sum(f["mask"] for f in fields if f["sw"] == "ro" and f["hw"] == "none")
            m["reset"] = sum((f["reset"] or 0) << f["lo"] for f in fields)
            m["all_const"] = m["const"] == m["valid"]
            m["members"] = members_of(fields)
            names[name], addrs[addr] = m, name
            csrs.append(m)
    for m in csrs:
        if not m["view"]:
            continue
        target = names.get(m["view"]["of"])
        if target is None or target["view"]:
            fail(f"{m['name']}: a view of {m['view']['of']}, which is not a CSR with fields")
        m["target"] = target
        want = m["view"].get("fields")
        if want is None:
            m["pack"] = None
            m["valid"], m["sw_write"] = target["valid"], target["sw_write"]
        else:
            by_name = {f["name"]: f for f in target["fields"]}
            pack, at = [], 0
            for fn in want:
                if fn not in by_name:
                    fail(f"{m['name']}: {target['name']} has no field {fn}")
                pack.append({"field": by_name[fn], "at": at})
                at += by_name[fn]["width"]
            m["pack"] = pack
            m["valid"] = (1 << at) - 1
            m["sw_write"] = sum(((1 << p["field"]["width"]) - 1) << p["at"]
                                for p in pack if p["field"]["sw"] == "rw")
        if m["read_only"]:
            m["sw_write"] = 0
    for m in csrs:
        texts(m)
    for g in groups:
        g["csrs"] = [names[c["name"]] for c in g["csrs"]]
    state = [m for m in csrs if not m["view"] and m["fields"] and not m["all_const"]]
    views = [m for m in csrs if m["view"]]
    return {"groups": groups, "csrs": csrs, "state": state, "views": views}


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("config", help="the design's CSR YAML")
    parser.add_argument("--root", required=True, help="repository root, outputs are relative to it")
    parser.add_argument("--check", action="store_true",
                        help="do not write, fail when outputs are missing or differ")
    args = parser.parse_args()

    with open(args.config) as f:
        config = yaml.safe_load(f)
    generate = config.pop("generate", [])
    return render_outputs(model(config["groups"]), generate, args.config, args.root,
                          args.check, tool="csr_gen", trim=True)


if __name__ == "__main__":
    sys.exit(main())
