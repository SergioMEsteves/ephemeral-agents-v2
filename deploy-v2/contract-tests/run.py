#!/usr/bin/env python3
"""V2 contract test suite — the reusable suite (platform §9.6 lesson 2:
"contract tests before gates, not during them"). Replaces V1's
per-milestone scripts for the contract boundaries; the milestone-specific
integration tests (deploy-v2/m*/tests) stay where they are.

Contracts covered (each names the artifact it proves — lesson 3):
  1. message-v1   — schemas/message-v1.json: required fields, enums,
                    additive fields (priority, approval_hash), rejection
                    of unknown fields and bad values.
  2. catalog      — the roster index.json shape every consumer parses
                    (manager ParseAgentIndex; CoS roster reads).
  3. spawn-env    — every executor entrypoint guards every env reference
                    (lesson 9: $TASK_PROMPT under set -u): no unguarded
                    ${VAR} expansions in set -u scripts.

Usage:
  python3 run.py                      # all contracts, repo defaults
  python3 run.py --contract message   # one contract
Exit 0 = all green; nonzero = failing contract (blocks the gate).
"""

import argparse
import glob
import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCHEMA = os.path.join(REPO, "schemas", "message-v1.json")
ROSTER = os.environ.get("EA_ROSTER_INDEX",
                        os.path.expanduser("~/Projects/AI/Agents/index.json"))
DEPLOY = os.path.join(REPO, "deploy")

results = []


def check(contract, name, ok, detail=""):
    results.append((contract, name, ok, detail))


# ---------------------------------------------------------------- message-v1
def test_message_contract():
    import jsonschema
    schema = json.load(open(SCHEMA))
    required = ["task_id", "agent_ref", "behavioral_spec", "repo_target", "requester"]
    uuid = "12345678-1234-4234-8234-123456789012"
    base = {"task_id": uuid, "agent_ref": "r#f", "behavioral_spec": "s",
            "repo_target": "rt", "requester": "o"}

    cases = [
        ("required-fields-present", base, True),
        ("optional-fields-absent-ok",
         {k: v for k, v in base.items() if k == "task_id"} | {k: base[k] for k in required}, True),
        ("ttl-below-minimum-rejected", base | {"ttl_s": 0}, False),
        ("ttl-valid", base | {"ttl_s": 900}, True),
        ("priority-enum-accepted", base | {"priority": "high"}, True),
        ("priority-out-of-enum-rejected", base | {"priority": "urgent"}, False),
        ("approval-hash-64hex-accepted", base | {"approval_hash": "a" * 64}, True),
        ("approval-hash-bad-pattern-rejected", base | {"approval_hash": "xyz"}, False),
        ("unknown-field-rejected", base | {"priority_x": 1}, False),
        ("missing-required-rejected",
         {k: v for k, v in base.items() if k != "requester"}, False),
    ]
    for name, doc, ok in cases:
        try:
            jsonschema.validate(doc, schema)
            valid = True
        except jsonschema.ValidationError:
            valid = False
        check("message-v1", name, valid == ok,
              "" if valid == ok else f"want {'valid' if ok else 'invalid'}")


# ------------------------------------------------------------------- catalog
def test_catalog():
    if not os.path.exists(ROSTER):
        check("catalog", "roster-index-present", False, f"not found: {ROSTER}")
        return
    idx = json.load(open(ROSTER))
    entries = idx["agents"] if isinstance(idx, dict) else idx
    check("catalog", "index-nonempty", len(entries) > 0)
    refs = set()
    bad = []
    for e in entries:
        for field in ("ref", "name", "role", "folder", "spec_ref"):
            if not e.get(field):
                bad.append(f"{e.get('ref', '?')} missing {field}")
        if e.get("ref") in refs:
            bad.append(f"duplicate ref {e['ref']}")
        refs.add(e.get("ref"))
    check("catalog", "entry-shape-complete-unique", not bad, "; ".join(bad[:5]))
    # every entry's spec_ref is folder-relative to the roster repo
    roster_root = os.path.dirname(ROSTER)
    missing = [e["spec_ref"] for e in entries
               if not os.path.exists(os.path.join(roster_root, e["spec_ref"]))]
    check("catalog", "spec-files-resolvable", not missing,
          f"{len(missing)} unresolvable spec_refs")


# ----------------------------------------------------------------- spawn-env
UNGUARDED = re.compile(r"\$\{[A-Za-z_][A-Za-z0-9_]*\}")  # ${VAR} without :- default


def test_spawn_env():
    scripts = sorted(glob.glob(os.path.join(DEPLOY, "m*", "executor*", "entrypoint*.sh")))
    if not scripts:
        check("spawn-env", "entrypoints-found", False, "no entrypoint scripts found")
        return
    for path in scripts:
        text = open(path).read()
        guarded = re.search(r"set\s+-[a-z]*u", text) is not None
        name = os.path.relpath(path, REPO)
        if not guarded:
            check("spawn-env", f"{name}: set -u", False, "entrypoint lacks set -u")
            continue
        # under set -u every ${VAR} must carry a default (:- or :=) — the
        # V1 lesson: an unguarded $TASK_PROMPT crashes the entrypoint.
        # ${VAR%s}/${VAR#pat} are operator expansions on already-set vars —
        # not unguarded references. $VAR and $(cmd) forms are out of scope
        # (set -u catches bare $VAR; $(cmd) is command substitution).
        plain = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}")
        assign = re.compile(r"^\s*(?:readonly\s+)?(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=")
        offenders = []
        assigned = set()
        for lineno, line in enumerate(text.splitlines(), 1):
            if (m := assign.match(line)):
                assigned.add(m.group(1))
            for m in UNGUARDED.finditer(line):
                tok = m.group(0)
                if re.search(re.escape(tok) + r":?[-+=?]", line):
                    continue
                # operator expansion? (${VAR<op>...} with op = % or #)
                if not plain.fullmatch(tok):
                    continue
                # plainly assigned earlier in the script → defined under set -u
                fm = plain.fullmatch(tok)
                if fm is None:
                    continue
                var = fm.group(1)
                if var in assigned:
                    continue
                offenders.append(f"line {lineno}: {tok}")
        check("spawn-env", f"{name}: all ${{VAR}} guarded", not offenders,
              "unguarded: " + ", ".join(offenders[:5]))


CONTRACTS = {"message": test_message_contract,
             "catalog": test_catalog,
             "spawn-env": test_spawn_env}


def main():
    ap = argparse.ArgumentParser(description="V2 contract test suite")
    ap.add_argument("--contract", choices=sorted(CONTRACTS), help="run one contract only")
    args = ap.parse_args()
    (CONTRACTS[args.contract] if args.contract else
     list(CONTRACTS.values()) and [f() for f in CONTRACTS.values()])
    failed = 0
    for contract, name, ok, detail in results:
        mark = "PASS" if ok else "FAIL"
        if not ok:
            failed += 1
        print(f"[{contract}] {mark} {name}" + (f" — {detail}" if detail and not ok else ""))
    print(f"\n{len(results) - failed}/{len(results)} checks green")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
