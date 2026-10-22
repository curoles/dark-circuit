#!/usr/bin/env python3
"""sv2doxy: SystemVerilog to C++ for Doxygen (FILTER_PATTERNS), one output line per input line.

Bare minimum: a block comment at the start of a line outside a module becomes
documentation (/** */) of the module after it, the module a class, its ports public members
with their trailing // comment (///<); every other line is empty, so Doxygen's line numbers
are the lines of the .sv file. The path of the file gives the class a group (@ingroup: the
directory under rtl/lib, or the design under rtl/design) and, when the module exists in
several versions (behave/struct, generic/cell, ...), a namespace named after the directory
of its version.

Usage: sv2doxy.py <file.sv>; Doxygen runs it on every input file and reads its output.

@author    Igor Lesik
@copyright 2026 Igor Lesik, MIT License
"""
import os
import re
import sys

MODULE = re.compile(r"^\s*module\s+(\w+)")
PORT = re.compile(r"^\s*(input|output|inout)\s+(.*?)\s*\b(\w+)\s*,?\s*(?://\s*(.*))?$")
END_MODULE = re.compile(r"^\s*endmodule\b")

# Directories that hold one version of a module, and the namespace of that version.
VERSIONS = {"behave": "Behave", "struct": "Struct", "generic": "Generic", "cell": "Cell",
            "builtin": "Builtin", "cmos": "Cmos", "tsmc": "Tsmc"}


def place(path):
    """Group and version namespace of a file: rtl/lib/<group>/.../<version>/<file>,
    rtl/design/<design>/<file> (the design is the group)."""
    parts = os.path.abspath(path).split(os.sep)
    group = None
    if "rtl" in parts:
        rest = parts[len(parts) - parts[::-1].index("rtl"):]
        if len(rest) >= 2 and rest[0] in ("lib", "design"):
            group = rest[1]
    return group, VERSIONS.get(parts[-2])


def convert(lines, group, namespace):
    out = []
    state = "top"       # top, comment (documentation comment), ports, body
    for text in lines:
        code = text.split("//")[0]
        if state == "comment":
            out.append(text)
            if "*/" in text:
                state = "top"
        elif state == "top":
            m = MODULE.match(text)
            if text.startswith("/*"):
                out.append("/**" + text[2:])
                if "*/" not in text[2:]:
                    state = "comment"
            elif m:
                ns = "namespace %s { " % namespace if namespace else ""
                ingroup = "/** @ingroup %s */ " % group if group else ""
                out.append("%s%sclass %s { public:" % (ns, ingroup, m.group(1)))
                state = "body" if re.search(r"\)\s*;", code) else "ports"
            else:
                out.append("")
        elif state == "ports":
            m = PORT.match(text)
            if m:
                direction, typ, name, comment = m.groups()
                decl = "%s<%s> %s;" % (direction, typ or "wire", name)
                out.append(decl + (" ///< " + comment if comment else ""))
            else:
                out.append("")
            if re.search(r"\)\s*;", code):
                state = "body"
        else:  # body
            if END_MODULE.match(text):
                out.append("};" + (" }" if namespace else ""))
                state = "top"
            else:
                out.append("")
    return out


def main():
    lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
    sys.stdout.write("\n".join(convert(lines, *place(sys.argv[1]))))


if __name__ == "__main__":
    main()
