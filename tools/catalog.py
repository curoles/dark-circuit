#!/usr/bin/env python3
"""Generate CATALOG.md: every module, package and macro file of rtl/lib as a YAML tree.

An entry is a module (or package, interface, macro file) with the first sentence of the
comment above it (the file's header comment for the first module of a file), its versions
(the behave/struct/comb/pipe directories, gate/generic and gate/cell), its path, its test
directory when there is one and the kb records whose code anchors point into it. Entries sit
in the tree of rtl/lib's directories; a block's own directory (block/fifo for Fifo) is not
a level of its own.

  catalog.py --root <repo>          write CATALOG.md
  catalog.py --root <repo> --check  exit 1 when CATALOG.md is not what this would write
"""
import argparse
import os
import re
import sys

import yaml

LIB = "rtl/lib"
VERSION_DIRS = {"behave", "struct", "comb", "pipe"}
# Directories right under these that are versions of the same modules (the same names).
GROUP_VERSION_DIRS = {"gate": {"generic", "cell"}, "cell": {"builtin", "cmos", "generic", "tsmc"}}
# Top-level directories that come last, in this order; the others alphabetically before them.
LAST = ["block", "part", "gate", "cell"]
# The version whose description and path an entry shows, first found in this order.
PREFERRED = ["behave", "generic", "comb"]
DECL = re.compile(r"^\s*(module|package|interface)\s+(\w+)", re.M)
COMMENT = re.compile(r"/\*(.*?)\*/", re.S)
# Which version a header describes: the entry's versions say it.
SUFFIXES = [", behavioral", "; behavioral", ", made of blocks and gates",
            "; made of blocks and gates", ", made of gates", "; made of gates",
            ", made of blocks", "; made of blocks"]


def summary(comment):
    """The first sentence of a /* ... */ comment's first paragraph."""
    lines = []
    for raw in comment.split("\n"):
        s = raw.strip()
        if s.startswith("*"):
            s = s[1:].strip()
        if not s:
            if lines:
                break
            continue
        if s.startswith("@"):
            break
        lines.append(s)
    text = " ".join(lines)
    m = re.match(r"(.*?[.!?])(\s+[A-Z(]|$)", text)
    if m:
        text = m.group(1)
    text = text.rstrip(".")
    for suf in SUFFIXES:
        if text.endswith(suf):
            text = text[: -len(suf)]
    # Which version it is, and kb references, are elsewhere in the entry.
    text = re.sub(r"[,;] behavioral\b", "", text)
    text = re.sub(r"\s*\(kb [^)]*\)", "", text)
    return text


def declarations(text):
    """(kind, name, comment) of every module, package and interface of a file."""
    out = []
    header = COMMENT.search(text)
    for m in DECL.finditer(text):
        before = text[: m.start()]
        # The comment right above the declaration (only `include lines and blanks between),
        # else the file's header comment.
        comment = None
        last = None
        for c in COMMENT.finditer(before):
            last = c
        if last is not None:
            gap = before[last.end():]
            if all(not l.strip() or l.strip().startswith("`") or l.strip().startswith("//")
                   for l in gap.split("\n")):
                comment = last.group(1)
        if comment is None and header is not None:
            comment = header.group(1)
        out.append((m.group(1), m.group(2), comment or ""))
    return out


def split_path(rel):
    """rtl/lib-relative path of a file -> (home without version dirs, version or None)."""
    parts = rel.split("/")[:-1]
    version = None
    home = []
    for i, p in enumerate(parts):
        if p in VERSION_DIRS or (i == 1 and p in GROUP_VERSION_DIRS.get(parts[0], ())):
            version = p
        else:
            home.append(p)
    return "/".join(home), version


def kb_index(root):
    """Code anchor path -> kb record ids."""
    index = []
    kb = os.path.join(root, "kb")
    for d, _, files in os.walk(kb):
        for f in files:
            if not f.endswith(".yaml"):
                continue
            p = os.path.join(d, f)
            rid = os.path.relpath(p, kb)[:-5]
            try:
                rec = yaml.safe_load(open(p))
            except yaml.YAMLError:
                continue
            for a in (rec or {}).get("code", []) or []:
                index.append((str(a).partition("#")[0], rid))
    return index


def collect(root):
    entries = {}   # name -> entry
    lib = os.path.join(root, LIB)
    for d, dirs, files in os.walk(lib):
        dirs.sort()
        for f in sorted(files):
            if not (f.endswith(".sv") or f.endswith(".svh")):
                continue
            path = os.path.join(d, f)
            rel = os.path.relpath(path, lib)
            text = open(path, errors="replace").read()
            home, version = split_path(rel)
            stem = f.rsplit(".", 1)[0]
            decls = declarations(text) if f.endswith(".sv") else []
            if f.endswith(".svh"):
                c = COMMENT.search(text)
                decls = [("macros", f, c.group(1) if c else "")]
            for kind, name, comment in decls:
                own_dir = os.path.basename(home) == stem
                position = os.path.dirname(home) if own_dir else home
                where = LIB + "/" + (home if own_dir else rel)
                e = entries.setdefault(name, {"kind": kind, "position": position,
                                              "path": where, "versions": [], "what": "",
                                              "stem": stem, "home": home, "own_dir": own_dir,
                                              "rank": len(PREFERRED)})
                if version and version not in e["versions"]:
                    e["versions"].append(version)
                # The description and path of the preferred version (else the first found).
                rank = PREFERRED.index(version) if version in PREFERRED else len(PREFERRED)
                if comment and (not e["what"] or rank < e["rank"]):
                    e["what"] = summary(comment)
                    e["path"] = where
                    e["rank"] = rank
    return entries


def finish(root, entries):
    index = kb_index(root)
    for name, e in entries.items():
        # A block in its own directory: the test of that directory; a file: a test of its
        # name next to it (test/part/<stem>), or the group's test (test/gate).
        tests = ["test/" + e["home"]] if e["own_dir"] else \
                ["test/" + e["position"] + "/" + e["stem"]]
        if e["versions"] and not e["own_dir"]:
            tests.append("test/" + e["home"])
        for t in tests:
            if os.path.isdir(os.path.join(root, t)):
                e["test"] = t
                break
        p = e["path"]
        e["kb"] = sorted({rid for a, rid in index
                          if a == p or a.startswith(p.rstrip("/") + "/")})


def q(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render(entries):
    tree = {}
    for name, e in entries.items():
        node = tree
        for p in [x for x in e["position"].split("/") if x]:
            node = node.setdefault(p, {})
        node.setdefault("", []).append((name, e))
    out = []

    def walk(node, depth):
        ind = "  " * depth
        for name, e in sorted(node.get("", []), key=lambda x: x[0].lower()):
            out.append(f"{ind}{name}:")
            if e["kind"] != "module":
                out.append(f"{ind}  kind: {e['kind']}")
            what = q(e["what"]) if e["what"] else '""  # no description'
            out.append(f"{ind}  what: {what}")
            if e["versions"]:
                out.append(f"{ind}  versions: [{', '.join(sorted(e['versions']))}]")
            out.append(f"{ind}  path: {e['path']}")
            if e.get("test"):
                out.append(f"{ind}  test: {e['test']}")
            if e["kb"]:
                out.append(f"{ind}  kb: [{', '.join(e['kb'])}]")
        keys = sorted(x for x in node if x)
        if depth == 0:
            # Most readers look for blocks; gates and cells come last.
            keys = [k for k in keys if k not in LAST] + [k for k in LAST if k in keys]
        for k in keys:
            out.append(f"{ind}{k}:")
            walk(node[k], depth + 1)

    walk(tree, 0)
    return "\n".join(out) + "\n"


HEAD = """<!-- THIS FILE IS GENERATED, DO NOT EDIT MANUALLY! tools/catalog.py (make catalog) -->
# Catalog of the library (rtl/lib)

Generated by `tools/catalog.py` (`make catalog`): change the header comment of a module and
run it again. `make kb` checks that this file is up to date.

Every module, package and macro file of `rtl/lib`, in the tree of its directories: `what` is
the first sentence of its header comment, `versions` the behave/struct (or other) versions,
`path` where it is, `test` its test directory, `kb` the kb records that point into it. Read it
before adding a block: the block you need may exist under another name.

```yaml
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--out")
    a = ap.parse_args()
    entries = collect(a.root)
    finish(a.root, entries)
    text = HEAD + render(entries) + "```\n"
    yaml.safe_load(render(entries))     # the tree is valid YAML
    target = a.out or os.path.join(a.root, "CATALOG.md")
    if a.check:
        old = open(target).read() if os.path.exists(target) else ""
        if old != text:
            print("CATALOG.md is not up to date: run make catalog")
            return 1
        return 0
    open(target, "w").write(text)
    missing = [n for n, e in entries.items() if not e["what"]]
    print(f"catalog: {len(entries)} entries, {len(missing)} without a description")
    if missing:
        print("  " + ", ".join(sorted(missing)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
