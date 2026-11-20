---
name: ea-install
description: Use when the owner asks to install the agent system estate.
version: 1.0.1
author: Ronald A Steinhauer (arvisdev) / Hermes Agent
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [install, deploy, estate, ephemeral-agents]
---

# ea-install — drive the ephemeral-agents estate install

## When to Use

The owner asks to install, build, or rebuild the ephemeral-agents estate
("run the install", "build the system from inputs.yaml"). Requires: a
LOCAL workstation session (never a remote gateway or CoS profile), the
repo cloned, and inputs collected per INSTALL-INPUTS-CHECKLIST.md. Not
for day-to-day estate use or project onboarding.

You are executing `deploy-v2/RUNBOOK-V2-BUILD.md` on behalf of the user.
The runbook is the source of truth; this skill is the agent-execution
layer over it. Do not improvise around it.

## Hard rules (never violate)

1. **Refuse to run from a remote/CoS session.** This skill drives the
   workstation's build machine only. If the current session is a remote
   gateway or a project CoS profile, stop and say why: an agent must never
   deploy its own estate.
2. **Never read secret values.** You may read `inputs.yaml` (paths only —
   the renderer enforces this) and you may COPY files onto VMs, but you
   never cat, print, or log a key/token/password. Terminal output that
   masks secrets is not proof of safety — verify by path, not by display.
3. **Never skip a stage or a gate.** Order is fixed: S0→S7. Each stage is
   `--check-only` first, then apply, then its gate. A stage does not begin
   until the previous stage's gate has PASSED.
4. **Stop at every gate and report.** Default mode: after each gate, print
   the gate result and the evidence path, then ask the owner to proceed
   (the runbook's sign-before-next rule). Only run unattended end-to-end
   if the owner explicitly said "auto-proceed" in the same conversation.
5. **On a failed gate:** diagnose from the stage's evidence output, attempt
   ONE root-cause fix, re-run the gate. If it fails again, STOP and surface
   to the owner — never attempt a second fix without approval.
6. **Nothing leaves the machines.** Evidence stays under `deploy-v2/mN/evidence/`
   (gitignored raw, committed summaries); the repo is the record.

## Procedure

### 0. Pre-flight (all read-only; abort on any failure)

1. Repo present: `~/Projects/AI/ephemeral-agents-v2` (or the path the
   owner gives). Confirm `deploy-v2/inputs.yaml` exists — if not, point
   the owner at `deploy-v2/INSTALL-INPUTS-CHECKLIST.md` and
   `deploy-v2/inputs.yaml.example` and STOP (do not invent values).
2. Workstation tooling: docker+buildx, go ≥1.22, `temporal` CLI, `gh`
   logged in, rsync, python3 with `pyyaml`+`jsonschema`.
3. Validate inputs: `python3 deploy-v2/render-inputs.py deploy-v2/inputs.yaml --check`.
   On failure, print every problem and STOP — the owner fixes the file,
   not you.
4. SSH reachability, BatchMode: for each machine in inputs.yaml, run
   `ssh -o BatchMode=yes <user>@<ip> 'echo ok && sudo -n true'`. Any
   failure = STOP with the specific machine and reason.
5. Report the pre-flight table (tool ✓/✗ per item) and ask: "Pre-flight
   green. Proceed to S0 check-only?"

### 1. Stage loop (per the runbook stage table S0→S7)

For each stage:
1. Run its `--check-only`. Report what it found. Confirm with owner if
   anything is unexpected.
2. Apply (the stage's install/apply command). Stream or tail the log; on
   any non-zero exit, go to the failure protocol.
3. Run the stage's gate. Capture the result and the evidence path.
4. Report: stage name, gate PASS/FAIL, evidence path, what comes next.
   Wait for the owner's go (unless auto-proceed was granted).

Stage-specific notes the agent must honor:
- **Container engine (S0):** the choice lives in `inputs.yaml`
  (`config.engine`) and is carried by `render-inputs.py` into
  `hosts.env` as `ENGINE=`. `docker` (default) = today's estate unchanged.
  `podman` = rootless Podman on the EXECUTION VM only (run as the `poc`
  user, never root); every other VM stays Docker. Never override the
  choice by hand — branch through `xb_engine()`.
- **S3 queue declaration:** `ea-tasks` is declared ONCE with
  `x-max-priority` — never re-declare with different args (a known ledger
  entry).
- **S4/S5/S6 env staging:** every secret lands 0600 gitignored at the
  path the staging plan printed. After staging, verify by checking the
  file EXISTS and its permissions, never by displaying content.
- **S6 CoS profile:** the env must be exactly the allow-list; run the
  negative assertion (the denial-list check), not just the positive one.
- **S7 desktop connection:** you cannot click the owner's Desktop. Hand
  over the seven-step procedure (book Special 3) with the session-token
  file path, and wait for the owner's "Reachable" confirmation.

### 2. Completion report

After S7: print the full gate table (all stages, all gates, evidence
paths), remind the owner to sign the TPs, commit evidence summaries and
the decision-log entry, and push. Then STOP — post-install onboarding
(bots, projects, tracker) is separate work.

## Failure protocol

1. Read the failing stage's evidence output. Identify the failing check.
2. Check the issue ledger (`version 2/V2-issue-ledger.md`) for a matching
   entry — most failures have a recorded root cause and rule.
3. Attempt one fix. Re-run the gate.
4. Second failure → stop, surface to the owner with: the failing check,
   what you tried, the evidence path, and your recommendation.
