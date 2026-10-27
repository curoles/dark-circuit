#!/usr/bin/env python3
"""Check the knowledge base kb/ (kb/README.md): records, anchors, links, @kb: tags.

Usage:
    kb_check.py --root <repo>

Checks:
- every kb/**/*.yaml is a YAML mapping with type, title, date and the fields of its type,
  and no other fields;
- every anchor (code, checked_by, guarded_by) names an existing file or directory, and its
  #name is in the file as a whole word;
- every relies_on is the id of an existing record;
- every `@kb: <id>` in the files of the repository names an existing record;
- every directory of kb/ mirrors a directory of the repository.
Lists the records that no @kb: tag points to (not an error). Exits 1 on errors.
"""
import argparse
import datetime
import os
import re
import sys

import yaml

COMMON_REQUIRED = {"type", "title", "date"}
COMMON_OPTIONAL = {"evidence", "code", "relies_on"}
TYPES = {
    "decision":    ({"question", "decision", "why"}, {"rejected"}),
    "invariant":   ({"statement", "why"}, {"checked_by"}),
    "measurement": ({"what", "result", "how"}, {"guarded_by"}),
    "dropped":     ({"tried", "result", "why_dropped"}, set()),
}
ANCHOR_FIELDS = ("code", "checked_by", "guarded_by")
# Where @kb: tags may be: the repository without kb/ itself, old code and build output.
SKIP_DIRS = {".git", "kb", "old2020", "build", "__pycache__"}
TAG_FILES = re.compile(r".*\.(sv|svh|v|S|s|c|h|py|cmake|txt|yaml|yml|j2|flist|md|ld)$|Makefile$")
# An id has at least one "/" (it is a path): "@kb:" in prose is not a tag.
TAG = re.compile(r"@kb:\s*([A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+)")


def load_records(root, errors):
    """id -> record of every kb/**/*.yaml."""
    records = {}
    kb = os.path.join(root, "kb")
    for dirpath, _, files in os.walk(kb):
        for f in sorted(files):
            if not f.endswith(".yaml"):
                continue
            path = os.path.join(dirpath, f)
            rid = os.path.relpath(path, kb)[:-len(".yaml")]
            try:
                with open(path) as fh:
                    rec = yaml.safe_load(fh)
            except yaml.YAMLError as e:
                errors.append(f"kb/{rid}.yaml: not YAML: {e}")
                continue
            if not isinstance(rec, dict):
                errors.append(f"kb/{rid}.yaml: not a mapping")
                continue
            records[rid] = rec
    return records


def check_fields(rid, rec, errors):
    t = rec.get("type")
    if t not in TYPES:
        errors.append(f"kb/{rid}.yaml: type {t!r}, expected one of {', '.join(TYPES)}")
        return
    required, optional = TYPES[t]
    missing = sorted((COMMON_REQUIRED | required) - rec.keys())
    unknown = sorted(rec.keys() - COMMON_REQUIRED - COMMON_OPTIONAL - required - optional)
    if missing:
        errors.append(f"kb/{rid}.yaml: missing {', '.join(missing)}")
    if unknown:
        errors.append(f"kb/{rid}.yaml: unknown fields {', '.join(unknown)}")
    if "date" in rec and not isinstance(rec["date"], datetime.date):
        errors.append(f"kb/{rid}.yaml: date {rec['date']!r} is not YYYY-MM-DD")
    for item in rec.get("rejected") or []:
        if not isinstance(item, dict) or set(item) != {"choice", "why_not"}:
            errors.append(f"kb/{rid}.yaml: rejected item without choice and why_not: {item!r}")


def check_anchor(root, rid, anchor, errors):
    path, _, name = str(anchor).partition("#")
    full = os.path.join(root, path)
    if not os.path.exists(full):
        errors.append(f"kb/{rid}.yaml: anchor {anchor}: no {path}")
    elif name:
        if os.path.isdir(full):
            errors.append(f"kb/{rid}.yaml: anchor {anchor}: {path} is a directory, no #name")
            return
        with open(full, errors="replace") as fh:
            text = fh.read()
        if not re.search(r"(?<![A-Za-z0-9_])" + re.escape(name) + r"(?![A-Za-z0-9_])", text):
            errors.append(f"kb/{rid}.yaml: anchor {anchor}: {name} is not in {path}")


def tags(root):
    """(file, line number, id) of every @kb: tag in the repository."""
    for dirpath, dirnames, files in os.walk(root):
        rel = os.path.relpath(dirpath, root)
        dirnames[:] = [d for d in dirnames if not (rel == "." and d in SKIP_DIRS)
                       and d not in {".git", "__pycache__"}]
        for f in sorted(files):
            if not TAG_FILES.match(f):
                continue
            path = os.path.join(dirpath, f)
            with open(path, errors="replace") as fh:
                for n, line in enumerate(fh, 1):
                    for m in TAG.finditer(line):
                        yield os.path.relpath(path, root), n, m.group(1).rstrip(".")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", required=True, help="repository root")
    args = ap.parse_args()
    root = os.path.abspath(args.root)
    errors = []

    records = load_records(root, errors)
    for rid, rec in sorted(records.items()):
        check_fields(rid, rec, errors)
        for field in ANCHOR_FIELDS:
            for anchor in rec.get(field) or []:
                check_anchor(root, rid, anchor, errors)
        for other in rec.get("relies_on") or []:
            if other not in records:
                errors.append(f"kb/{rid}.yaml: relies_on {other}: no such record")

    kb = os.path.join(root, "kb")
    for dirpath, _, _ in os.walk(kb):
        rel = os.path.relpath(dirpath, kb)
        if rel != "." and not os.path.isdir(os.path.join(root, rel)):
            errors.append(f"kb/{rel}/: mirrors no directory {rel} of the repository")

    pointed = set()
    for path, n, rid in tags(root):
        pointed.add(rid)
        if rid not in records:
            errors.append(f"{path}:{n}: @kb: {rid}: no such record")

    for e in errors:
        print(e)
    unpointed = sorted(set(records) - pointed)
    print(f"kb: {len(records)} records, {len(errors)} errors"
          + (f"; no @kb: tag points to {', '.join(unpointed)}" if unpointed else ""))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
