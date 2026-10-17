#!/usr/bin/env python3
"""Generate files from a YAML configuration and Jinja2 templates.

Usage:
    config_gen.py --root <repo> <config.yaml> [--check]

The YAML file has configuration values and a list `generate` of
{template, output}: template relative to the directory of the YAML file,
output relative to --root. Every template is rendered with the configuration
values (all YAML keys except `generate`) and with `generated_note`, a line that
tells where the file comes from; templates put it in their comment syntax.
Filters for number literals: sv_hex(width) and c_hex(width).

A file is written only when its content changes, so builds do not redo work.
--check writes nothing and exits 1 when an output is missing or differs.
"""
import argparse
import os
import sys

import jinja2
import yaml


def sv_hex(value, width):
    """SystemVerilog sized hex literal: sv_hex(0, 32) -> 32'h0000_0000."""
    digits = f"{value:0{(width + 3) // 4}x}"
    groups = [digits[max(0, i - 4):i] for i in range(len(digits), 0, -4)][::-1]
    return f"{width}'h{'_'.join(groups)}"


def c_hex(value, width=32):
    """C hex literal: c_hex(0) -> 0x00000000."""
    return f"0x{value:0{(width + 3) // 4}x}"


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("config", help="YAML configuration file")
    parser.add_argument("--root", required=True, help="repository root, outputs are relative to it")
    parser.add_argument("--check", action="store_true",
                        help="do not write, fail when outputs are missing or differ")
    args = parser.parse_args()

    with open(args.config) as f:
        config = yaml.safe_load(f)
    generate = config.pop("generate", [])
    config_dir = os.path.dirname(os.path.abspath(args.config))
    config_name = os.path.relpath(os.path.abspath(args.config), args.root)

    env = jinja2.Environment(
        loader=jinja2.FileSystemLoader(config_dir),
        undefined=jinja2.StrictUndefined,  # unknown variable in a template is an error
        keep_trailing_newline=True,
    )
    env.filters["sv_hex"] = sv_hex
    env.filters["c_hex"] = c_hex

    stale = []
    for item in generate:
        template, output = item["template"], item["output"]
        note = f"GENERATED from {config_name} and {template} by tools/config_gen.py, do not edit"
        text = env.get_template(template).render(config, generated_note=note)
        path = os.path.join(args.root, output)
        old = None
        if os.path.exists(path):
            with open(path) as f:
                old = f.read()
        if old == text:
            continue
        if args.check:
            stale.append(output)
        else:
            with open(path, "w") as f:
                f.write(text)
            print(f"config_gen: wrote {output}")

    if stale:
        print("config_gen: out of date, run `make config`: " + ", ".join(stale), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
