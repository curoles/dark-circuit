#!/usr/bin/env python3
"""sv2doxy: SystemVerilog to C++ for Doxygen (FILTER_PATTERNS), one output line per input line.

Bare minimum: a block comment at the start of a line outside a module becomes
documentation (/** */) of the module after it, the module a class, its ports public members
with their trailing // comment (///<); every other line is empty, so Doxygen's line numbers
are the lines of the .sv file.

Usage: sv2doxy.py <file.sv>; Doxygen runs it on every input file and reads its output.

@author    Igor Lesik
@copyright 2026 Igor Lesik, MIT License
"""
import re
import sys

MODULE = re.compile(r"^\s*module\s+(\w+)")
PORT = re.compile(r"^\s*(input|output|inout)\s+(.*?)\s*\b(\w+)\s*,?\s*(?://\s*(.*))?$")
END_MODULE = re.compile(r"^\s*endmodule\b")


def convert(lines):
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
                out.append("class %s { public:" % m.group(1))
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
                out.append("};")
                state = "top"
            else:
                out.append("")
    return out


def main():
    lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
    sys.stdout.write("\n".join(convert(lines)))


if __name__ == "__main__":
    main()
