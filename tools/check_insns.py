#!/usr/bin/env python3
"""Instructions of RISC-V objects that a core does not decode.

Disassembles the objects (objdump -d -M no-aliases: the real instructions, no pseudo ones)
and lists every mnemonic with its count; a mnemonic that the core's decoder does not name
is marked and makes the exit status 1. The decoder's names are those of its kind case (the
encodings of RiscvInstrPkg in lines `NAME, NAME:  kind_enc = KIND_...`, rtl/design/mig3/
mig3_decode.sv): PADD_B is padd.b, REV8_RV32 is rev8.

Usage: check_insns.py --decode <decode.sv> --objdump <objdump> <object>...
"""
import argparse
import re
import subprocess
import sys


def decoded_mnemonics(path):
    names = set()
    for line in open(path):
        m = re.match(r"\s+([A-Z0-9_, ]+):\s+kind_enc\s*=\s*KIND_", line)
        if not m:
            continue
        for name in m.group(1).split(","):
            name = name.strip().lower()
            if name.endswith("_rv32"):
                name = name[:-len("_rv32")]
            names.add(name.replace("_", "."))
    return names


def used_mnemonics(objdump, obj):
    out = subprocess.run([objdump, "-d", "-M", "no-aliases", obj], check=True,
                         capture_output=True, text=True).stdout
    counts = {}
    for line in out.splitlines():
        m = re.match(r"\s+[0-9a-f]+:\s+[0-9a-f]{8}\s+(\S+)", line)
        if m:
            counts[m.group(1)] = counts.get(m.group(1), 0) + 1
    return counts


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--decode", required=True)
    p.add_argument("--objdump", required=True)
    p.add_argument("objects", nargs="+")
    a = p.parse_args()
    known = decoded_mnemonics(a.decode)
    unknown = 0
    for obj in a.objects:
        counts = used_mnemonics(a.objdump, obj)
        print(f"{obj}:")
        for name in sorted(counts):
            mark = "" if name in known else "   <- not decoded"
            unknown += name not in known
            print(f"  {name:12} {counts[name]:5}{mark}")
    if unknown:
        print(f"{unknown} instruction(s) the core does not decode")
    return 1 if unknown else 0


if __name__ == "__main__":
    sys.exit(main())
