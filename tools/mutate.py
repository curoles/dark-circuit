#!/usr/bin/env python3
"""Run the mutants of the tests: kb records of type mutants (kb/README.md).

Usage:
    mutate.py --root <repo> [--scratch DIR] [--sim verilator|icarus] [-j N] [FILTER ...]

A mutant changes the design (or forces a signal) the way a bug would; the test must catch
it. Each mutant of the selected records (every kb/**/mutants.yaml, or those whose id
contains a FILTER) runs in a scratch copy of the repository, never in the repository:
the copy is refreshed (rsync, without .git), the files rsync copied touched (it keeps the
repository's times, and a build older than them would not rebuild; touching every file
would make Verilator rebuild its whole model), the mutant applied, and the record's tests
built and run in the scratch build directory: a few seconds a mutant. Before the
mutants, each test runs once unmutated and must pass. Results:
  caught    a test failed; with expect: <name>, by the check DC_TEST_FAIL <name> or the
            assertion <name> (in the test's output)
  wrong     a test failed, but not by the check or assertion that expect names
  survived  every test passed (an error, unless the mutant says expect: survives and why)
  stale     an edit's old text is not in its file exactly once: that code changed, review
            the mutant
  invalid   the mutant did not build (or built with warnings): a broken mutant proves nothing
Exits 1 unless every mutant is caught or a survivor it expects.

A mutant (one item of the record's mutants list):
  name          what it breaks
  edits         list of {file, old, new}: text replacements, old exactly once in file
  python_code   Python run in the scratch copy, for what edits can not say; it gets root
                (the scratch copy, with a trailing /), replace(path, old, new) and glob
  verilog_code  SystemVerilog put at the test's hook (DC_TEST_MUTANT_HOOK), e.g. a force
  hook          the hook of verilog_code (default top)
  quiet         names of the test's checks that print instead of stopping (DcTestPkg)
  tests         the tests to run, instead of the record's
  expect        caught (default), survives (with why), or the name of a check or assertion
  why           why a mutant survives, or anything else worth saying
"""
import argparse
import glob as globmod
import os
import re
import subprocess
import sys
import time

import yaml

MACRO = "rtl/lib/macro"
TEST_SVH = MACRO + "/dark_circuit_test.svh"
HOOK = re.compile(r"`DC_TEST_MUTANT_HOOK\((\w+)\)")
# A warning of a simulator (Verilator's %Warning, Icarus's "file.sv:12: warning" or "sorry"),
# not one of make or cmake.
SIM_WARNING = re.compile(r"%Warning|\.svh?:\d+: (warning|sorry)")


def run(cmd, cwd=None):
    """Run a command; (exit code, output)."""
    p = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       text=True, errors="replace")
    return p.returncode, p.stdout


def records(root, filters):
    """(id, record) of every record of type mutants that matches a filter."""
    found = []
    kb = os.path.join(root, "kb")
    for dirpath, _, files in os.walk(kb):
        for f in sorted(files):
            if not f.endswith(".yaml"):
                continue
            rid = os.path.relpath(os.path.join(dirpath, f), kb)[:-len(".yaml")]
            with open(os.path.join(dirpath, f)) as fh:
                rec = yaml.safe_load(fh)
            if isinstance(rec, dict) and rec.get("type") == "mutants" and \
                    (not filters or any(x in rid for x in filters)):
                found.append((rid, rec))
    return sorted(found)


class Stale(Exception):
    pass


def replace(src, path, old, new):
    """old exactly once in src/path, replaced by new; else Stale."""
    full = os.path.join(src, path)
    if not os.path.isfile(full):
        raise Stale(f"{path}: no such file")
    with open(full) as fh:
        text = fh.read()
    n = text.count(old)
    if n != 1:
        raise Stale(f"{path}: old text found {n} times: {old[:60]!r}")
    with open(full, "w") as fh:
        fh.write(text.replace(old, new))


def refresh(root, src):
    """The scratch copy: the repository as it is, without .git (the build does not read it;
    its build directories are outside it). The files rsync copies (all the first time, then
    those the last mutant changed) get a fresh time, so that the build sees them."""
    os.makedirs(src, exist_ok=True)
    code, out = run(["rsync", "-a", "--delete", "--exclude=/.git", "--out-format=%i %n",
                     root + "/", src + "/"])
    if code:
        sys.exit("rsync failed:\n" + out)
    for line in out.splitlines():
        item, _, path = line.partition(" ")
        if item.startswith(">f"):       # a file received
            os.utime(os.path.join(src, path))


def apply(src, m):
    """Apply mutant m to the scratch copy; raises Stale."""
    for e in m.get("edits") or []:
        replace(src, e["file"], e["old"], e["new"])
    if m.get("python_code"):
        env = {"root": src + "/", "glob": globmod.glob,
               "replace": lambda p, o, n: replace(src, p, o, n)}
        exec(m["python_code"], env)     # the repository's own records: trusted code
    defines = []
    if m.get("verilog_code"):
        hook = m.get("hook", "top")
        hooks = set()
        for dirpath, _, files in os.walk(os.path.join(src, "test")):
            for f in files:
                if f.endswith((".sv", ".svh")):
                    with open(os.path.join(dirpath, f), errors="replace") as fh:
                        hooks.update(HOOK.findall(fh.read()))
        if hook not in hooks:
            raise Stale(f"no `DC_TEST_MUTANT_HOOK({hook}) in the tests")
        for h in hooks:
            with open(os.path.join(src, MACRO, f"dc_mutant_{h}.svh"), "w") as fh:
                fh.write(m["verilog_code"] if h == hook else "")
        defines.append("`define DC_MUTANT")
    if m.get("quiet"):
        defines.append('`define DC_TEST_QUIET "%s"' % ",".join(m["quiet"]))
    if defines:
        path = os.path.join(src, TEST_SVH)
        with open(path) as fh:
            text = fh.read()
        with open(path, "w") as fh:
            fh.write("// Mutant run (tools/mutate.py).\n" + "\n".join(defines) + "\n" + text)


def build_and_run(build, sim, tests, jobs):
    """('invalid', reason) or ('ran', [(test, failed, output)])."""
    results = []
    for t in tests:
        target = f"{t}.{sim}"
        code, out = run(["cmake", "--build", build, "-j", str(jobs), "--target", target])
        warnings = [ln for ln in out.splitlines() if SIM_WARNING.search(ln)]
        if code or warnings:
            first = next((ln for ln in out.splitlines()
                          if SIM_WARNING.search(ln) or "%Error" in ln or ": error" in ln),
                         "build failed")
            return "invalid", f"{target}: {first.strip()[:150]}"
        code, out = run(["ctest", "--test-dir", build, "-R", f"^{re.escape(target)}$",
                         "--output-on-failure", "--no-tests=error"])
        results.append((t, code != 0, out))
    return "ran", results


def verdict(m, results):
    """The result of a mutant whose tests ran: (result, detail)."""
    expect = m.get("expect", "caught")
    failed = [(t, out) for t, f, out in results if f]
    if expect == "survives":
        if failed:
            return "caught", f"expected to survive ({m.get('why', 'no why')}): update it"
        return "survived (expected)", m.get("why", "")
    if not failed:
        return "survived", "no test failed"
    if expect == "caught":
        return "caught", first_failure(failed[0][1])
    for t, out in failed:
        if f"DC_TEST_FAIL {expect}:" in out or f"assertion {expect} failed" in out:
            return "caught", f"by {expect}: {first_failure(out)}"
    return "wrong", f"not by {expect}: {first_failure(failed[0][1])}"


def first_failure(out):
    for ln in out.splitlines():
        if "DC_TEST_FAIL" in ln and "(quiet)" not in ln or "assertion" in ln or "%Fatal" in ln:
            return ln.strip()[:160]
    return "failed"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", required=True, help="repository root")
    ap.add_argument("--scratch", default="/tmp/dc_mutate", help="scratch directory")
    ap.add_argument("--sim", default="verilator", choices=("verilator", "icarus"))
    ap.add_argument("-j", type=int, default=2, help="build jobs (default 2)")
    ap.add_argument("filters", nargs="*", help="run only records whose id contains one")
    args = ap.parse_args()
    root = os.path.abspath(args.root)
    src = os.path.join(args.scratch, "src")
    build = os.path.join(args.scratch, f"build-{args.sim}")

    recs = records(root, args.filters)
    if not recs:
        sys.exit("no mutants records" + (f" matching {args.filters}" if args.filters else ""))

    refresh(root, src)
    if not os.path.exists(os.path.join(build, "CMakeCache.txt")):
        code, out = run(["cmake", "-S", src, "-B", build, "-DDARK_CIRCUIT_DESIGNS=",
                         "-DDARK_CIRCUIT_LIB_TESTS=ON",
                         "-DDARK_CIRCUIT_MAIN_SIMULATOR=" +
                         ("icarus" if args.sim == "icarus" else "AUTO")])
        if code:
            sys.exit("cmake failed:\n" + out[-2000:])

    # Every test unmutated first: a test that already fails would catch every mutant.
    tests = sorted({t for _, rec in recs for m in rec["mutants"]
                    for t in m.get("tests", rec["tests"])})
    state, results = build_and_run(build, args.sim, tests, args.j)
    if state == "invalid" or any(f for _, f, _ in results):
        sys.exit("the tests fail unmutated: " +
                 (results if state == "invalid" else
                  ", ".join(t for t, f, _ in results if f)))

    bad = 0
    for rid, rec in recs:
        print(f"== {rid}: {rec['title']}")
        for i, m in enumerate(rec["mutants"]):
            start = time.time()
            refresh(root, src)
            try:
                apply(src, m)
                state, results = build_and_run(build, args.sim, m.get("tests", rec["tests"]),
                                               args.j)
                if state == "invalid":
                    result, detail = "invalid", results
                else:
                    result, detail = verdict(m, results)
            except Stale as e:
                result, detail = "stale", str(e)
            ok = result in ("caught", "survived (expected)") and \
                not detail.startswith("expected to survive")
            bad += not ok
            print(f"  {i:2} {result:20} {m['name']} ({time.time() - start:.1f} s)")
            print(f"     {detail}", flush=True)
    refresh(root, src)
    print(f"mutants: {'all as expected' if not bad else f'{bad} not as expected'}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
