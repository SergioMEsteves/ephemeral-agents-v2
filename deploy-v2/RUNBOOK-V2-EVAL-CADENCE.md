# RUNBOOK-V2-EVAL-CADENCE — Layer-2 review + trajectory sampling

Established by ADR-0003 H3 (D-eval-ci), 2026-11-24. The judgment corpus is
the automated Layer-1 gate (CI: `.github/workflows/judgment-corpus.yml`).
This runbook owns what automation cannot judge.

## 1. Layer-2 review cadence (owner)

Review the corpus's judgmental dimension — decomposition quality, ambiguity
handling, escalation instincts — against real CoS behavior:

- **Trigger:** after ANY change to the CoS profile (persona, model, AGENTS.md
  rules), or at minimum once a month.
- **Method:** take the 3 most recent real CoS conversations (Desktop), read
  the proposals against the corpus's escalation/ambiguity fixtures, and ask:
  did the CoS escalate where the corpus says escalate? did it avoid
  submitting ambiguity? record the verdict (pass/concern) with the date in
  this file's log below.
- **Escape hatch:** two consecutive "concern" verdicts = treat as a P1 and
  run a focused persona amendment.

## 2. Monthly trajectory sampling

From the workstation:

```bash
ssh poc@<execution-vm> 'sudo bash -s' < deploy-v2/h3/trajectory-sample.sh
```

The script reports: task count in the retention window, success/fail split,
retry counts observed, TTL-kills, and any report whose executor crossed a
boundary flag (out-of-scope pushes, non-allowed destinations logged). Review
its output alongside the Layer-2 verdict; both live in this file's log.

## 3. Log

| Date | Layer-2 verdict | Trajectory sample | Notes |
|------|-----------------|-------------------|-------|
| 2026-11-24 | baseline established | n/a (gate created) | corpus 13 fixtures, CI live |
