# Judgment corpus — V2-M1 CoS pre-gate eval (non-signed)

> Specified in `V2-M1-cos-design.md` §7 (third-pass review condition 4,
> owner-approved). This directory is the runnable test asset the design
> describes; it is **not** part of the shipped system — it tests the CoS.

## What it is

A fixed, versioned set of input requests with expected routing outcomes.
The CoS (or any candidate CoS implementation) is run against these
inputs; its proposed packages are compared to the expected values.

**Two honest layers:**

- **Layer 1 — machine-checkable, scored exact-match, 100% required.**
  Fields checked per fixture: `agent_ref` (exact match), executor
  harness (`claude-code` | `hermes-agent`), priority class
  (`high` | `normal` | `low`), dependency edges, additive-vs-corrective
  label. Ambiguity fixtures check behavior instead: the CoS must
  **escalate to the owner and submit nothing**.
- **Layer 2 — the judgmental remainder, unscored, owner-reviewed.**
  Quality of the `behavioral_spec` text and elegance of the
  decomposition are recorded in the gate evidence as an owner review —
  never auto-scored. A green run means "the CoS routes correctly,"
  not "the CoS writes great specs."

## How to run

```bash
# 0. Self-check the corpus itself (fixture schema, refs valid in the
#    roster index.json, harness/priority enums):
python3 check.py --fixtures fixtures/ --roster /home/arvisdev/Projects/AI/Agents/index.json

# 1. Run each fixture input through the CoS under test and collect its
#    proposed packages into a run file (JSON: {"runs": {"<fixture-id>":
#    {"packages": [{"agent_ref", "harness", "priority", "mode"}...],
#     "dependencies": [[a, b], ...], "escalated": bool}}}):
#    (the run file is produced by the CoS operator procedure — not by
#     this corpus; the corpus does not drive the estate)

# 2. Score the run against Layer 1:
python3 check.py --fixtures fixtures/ --roster <index.json> --run <run.json>
```

**Pass rule:** Layer 1 at 100% blocks-or-clears TP signature (any miss
= defect); Layer 2 is recorded, not scored. The corpus is a
**non-signed pre-gate eval**: it gates TP-V2-M1 signature procedurally;
the signed structural assertions stay the plumbing.

## Re-run trigger (documented manual rule at M1)

A CoS persona commit or roster-context change requires a corpus re-run
before the next TP signature. When the contract test suite gains CI
(open-items queue item 8's direction), this corpus joins it.

## Contents

| Fixture | Case class it covers |
|---|---|
| F01 | straightforward routing — backend coding → claude-code |
| F02 | straightforward routing — business analysis → hermes-agent |
| F03 | harness edge — security-architect (IT, non-coding) → hermes-agent |
| F04 | harness edge — data-engineer ETL (coding) → claude-code |
| F05 | compliance work → hermes-agent, low priority |
| F06 | urgent defect → high priority, claude-code |
| F07 | dependency chain — analysis precedes implementation |
| F08 | parallel independence — three unrelated packages |
| F09 | additive change (new capability, D10) |
| F10 | corrective revision (references a prior artifact, D10) |
| F11 | ambiguity → escalate, submit nothing (D7d ask) |
| F12 | ambiguity → escalate, submit nothing (underspecified scope) |
| F13 | unit-test implementation → claude-code, normal |
