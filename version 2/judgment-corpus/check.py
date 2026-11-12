#!/usr/bin/env python3
"""Judgment-corpus Layer-1 checker (V2-M1 pre-gate eval, non-signed).

Modes:
  --self        validate the corpus itself: fixture schema, roster refs,
                harness/priority enums, dependency consistency. (default)
  --run F       score a CoS run file against Layer 1, exact match.

Run-file format (produced by the CoS operator procedure):
  {"runs": {"<fixture-id>": {
      "packages": [{"agent_ref","harness","priority","mode"}...],
      "dependencies": [["<agent_ref>","<agent_ref>"],...],
      "escalated": bool}}}

Pass rule: Layer 1 at 100% blocks-or-clears TP signature (any miss =
defect). Layer 2 (spec quality) is owner-reviewed, never scored here.
"""

import argparse
import json
import sys
from pathlib import Path

HARNESSES = {"claude-code", "hermes-agent"}
PRIORITIES = {"high", "normal", "low"}
MODES = {"additive", "corrective"}
AGENT_FIELDS = {"agent_ref", "harness", "priority", "mode"}


def load(path):
    with open(path) as f:
        return json.load(f)


def self_check(fixtures, roster):
    """Validate the corpus: schema, enums, refs, dependency consistency."""
    valid_refs = {a["ref"] for a in roster.get("agents", [])}
    errors = []
    ids = set()
    for fx in fixtures["fixtures"]:
        fid = fx.get("id")
        if not fid or fid in ids:
            errors.append(f"{fid}: missing or duplicate id")
            continue
        ids.add(fid)
        exp = fx.get("expected", {})
        for key in ("packages", "dependencies", "escalated"):
            if key not in exp:
                errors.append(f"{fid}: expected.{key} missing")
        if not isinstance(exp.get("escalated"), bool):
            errors.append(f"{fid}: expected.escalated must be boolean")
        if exp.get("escalated"):
            if exp.get("packages"):
                errors.append(f"{fid}: escalation fixture must expect packages=[]")
        for i, p in enumerate(exp.get("packages", [])):
            if AGENT_FIELDS - set(p):
                errors.append(f"{fid} pkg[{i}]: missing fields {AGENT_FIELDS - set(p)}")
            if p.get("agent_ref") not in valid_refs:
                errors.append(f"{fid} pkg[{i}]: agent_ref '{p.get('agent_ref')}' not in roster index")
            if p.get("harness") not in HARNESSES:
                errors.append(f"{fid} pkg[{i}]: bad harness {p.get('harness')!r}")
            if p.get("priority") not in PRIORITIES:
                errors.append(f"{fid} pkg[{i}]: bad priority {p.get('priority')!r}")
            if p.get("mode") not in MODES:
                errors.append(f"{fid} pkg[{i}]: bad mode {p.get('mode')!r}")
        refs = {p.get("agent_ref") for p in exp.get("packages", [])}
        for dep in exp.get("dependencies", []):
            if len(dep) != 2 or dep[0] not in refs or dep[1] not in refs:
                errors.append(f"{fid}: dependency {dep} references package-less or foreign refs")
    print(f"corpus self-check: {len(fixtures['fixtures'])} fixtures, "
          f"{len(errors)} error(s)")
    for e in errors:
        print("  ERROR:", e)
    return errors


def score(fixtures, roster, run):
    """Score a CoS run against Layer 1 — exact match."""
    errors = []
    total = passed = 0
    by_id = {fx["id"]: fx["expected"] for fx in fixtures["fixtures"]}
    for fid, exp in by_id.items():
        total += 1
        got = run.get("runs", {}).get(fid)
        if got is None:
            errors.append(f"{fid}: MISSING from run file")
            continue
        want_escalated = exp["escalated"]
        if bool(got.get("escalated")) != want_escalated:
            errors.append(f"{fid}: escalated={got.get('escalated')} want {want_escalated}")
            continue
        if want_escalated:
            if got.get("packages"):
                errors.append(f"{fid}: escalation fixture submitted {len(got['packages'])} package(s)")
                continue
        else:
            want_pkgs = sorted(
                (p["agent_ref"], p["harness"], p["priority"], p["mode"])
                for p in exp["packages"])
            got_pkgs = sorted(
                (p["agent_ref"], p["harness"], p["priority"], p["mode"])
                for p in got.get("packages", []))
            if want_pkgs != got_pkgs:
                errors.append(f"{fid}: package set mismatch\n    want {want_pkgs}\n    got  {got_pkgs}")
                continue
            want_deps = sorted(map(tuple, exp["dependencies"]))
            got_deps = sorted(map(tuple, got.get("dependencies", [])))
            if want_deps != got_deps:
                errors.append(f"{fid}: dependency mismatch\n    want {want_deps}\n    got  {got_deps}")
                continue
        passed += 1
    print(f"Layer 1: {passed}/{total} exact-match ({100 * passed / total:.0f}%)")
    print("VERDICT:", "PASS — blocks-or-clears TP signature" if passed == total
          else "FAIL — any miss is a defect (see errors)")
    for e in errors:
        print("  MISS:", e)
    return passed == total


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--fixtures", required=True, help="fixtures.json path")
    ap.add_argument("--roster", required=True, help="roster index.json path")
    ap.add_argument("--run", help="CoS run file to score (Layer 1)")
    args = ap.parse_args()

    fixtures = load(args.fixtures)
    roster = load(args.roster)
    errors = self_check(fixtures, roster)
    if errors:
        sys.exit(1)
    if args.run:
        ok = score(fixtures, roster, load(args.run))
        sys.exit(0 if ok else 1)
    print("corpus is valid and runnable; supply --run to score a CoS run")


if __name__ == "__main__":
    main()
