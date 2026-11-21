# TC-M3-03 — Failure paths (executor fails → error surfaced → reaped)

Date: 2026-11-14 · Executor: hermes · Image: ea/hermes-ephemeral:1.0.0
Method: direct `docker run` on vm-xb with the same env contract the lifecycle injects at spawn (fresh installation token per §1 issuance; revoked after the run).

## 3a — Unreachable AGENT_REPO_URL
- Env: `AGENT_REPO_URL=https://github.com/arvisdev/no-such-repo-xyz`, `AGENT_REF=ephemeral-org/eph-backend-engineer`
- Result: `exit:2`, fail message `agent repo unreachable or token rejected`
- Self-report with `error` field, `sources.agent_repo: false` (raw JSON below)

## 3b — AGENT_REF missing from index.json
- Env: `AGENT_REPO_URL=https://github.com/arvisdev/agent-roster`, `AGENT_REF=ephemeral-org/nonexistent`
- Result: `exit:2`, fail message `index miss: AGENT_REF 'ephemeral-org/nonexistent' not in index.json`
- Self-report captured (raw JSON below)

## Control (happy path, same session)
- `ephemeral-org/eph-backend-engineer` + valid token → `exit:0`, self-report with
  `persona_files: " persona.md skill-and-tools.md behavioral-spec.md"` (matches the catalog folder contents),
  `boot_ms: 644` — proves the two failures are path-specific, not environmental.

Verdict: **PASS (2/2 failure paths + control)** — matches the V1 TC-M3-03 evidence pattern.

## Raw self-reports
(see m3-failures-selfreports.txt — filed verbatim from /tmp/m3fail-{a,b,ctl}/self-report.json on vm-xb)
