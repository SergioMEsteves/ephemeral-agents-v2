# TP-M2 — M2 Lifecycle Test Procedure results (V2, ea-)

**Date:** 2026-11-14 · **Estate:** V2 (ea-), coexistence with V1 (/opt/poc) untouched
**DUT:** `ea/lifecycle:1.0.0`, `ea/worker:1.0.0`, `ea/executor-stub:1.0.0` — compose project `ea-m2`, vm-xb
**Companion:** `deploy-v2/m2/evidence/m2-tests.txt` (V1–V5), `install-m2.log`, `m2-report-snapshot.txt`, `m2-task-logs-list.txt`

## Mandatory cases

| ID | Case | Result | Evidence |
|---|---|---|---|
| TC-M2-01 | Clean path | **PASS** | V1: t001 success + reaped (`exited-0`), zero survivors |
| TC-M2-02 | Failure path | **PASS** | V2: exit-1 injected → status fail surfaced + reaped |
| TC-M2-03 | Timeout path | **PASS** | V3: hang, ttl 15 → reaped at TTL, timed-out surfaced |
| TC-M2-04 | **Crash recovery** (load-bearing) | **PASS** | V4: worker killed mid-activity → independent reaper reaped the orphan (`ttl` reason), zero survivors; workflow retries + clean final state |
| TC-M2-05 | 10 mixed runs, zero survivors | **PASS** | V5: 5 success / 3 failure / 2 timeout — 10/10 PASS, zero survivors after |
| TC-M2-06 | No-pull rule | **PASS** | pinned image deleted → lifecycle logs `no-pull deploy gate FAILED: pinned image absent; not serving`, health endpoint blocked (DNS/conn refused); image restored → /health 200 OK; zero pulls in logs |

## Informational

- I-M2-01: per-task logs in `/var/ea/tasks/<id>.log`; `/report` snapshot filed (`m2-report-snapshot.txt`)
- I-M2-02: stub spawn latency ~2.5 s spawn→exit (bounds for real images)

## Environment notes

- V2 compose project `ea-m2` (stub-only M2-era config — the M3-era executor switch lands with the M3 install); V1 stack untouched (`/opt/poc`, containers `m2-lifecycle-1`/`m2-worker-1` still up).
- Abort condition did NOT fire: TC-M2-04 passed on the first remediated run (reaper grace/interval wait corrected in a prior V1-era fix, carried forward).
- First run of the gate this build failed V1/V5 because the compose carried the M5-era executor default (`hermes`) — root cause: compose.yaml evolution drift (M5-era state in an M2-era gate). Fixed by restoring the M2-era stub-only compose; the M3 install writes the M3-era state. Recorded in the V2 issue ledger.

## Gate decision

**PASS** — TC-M2-01…06 all PASS → **M3 installation authorized**.

## Sign-off (D-signoff, 2026-11-04)

Signed on owner's behalf per standing authorization (2026-11-05): all-PASS with evidence filed.

| Field | Value |
|---|---|
| Signed by (HITL) | Owner (delegated to Hermes, standing authorization) |
| Date | 2026-11-14 |
| Evidence pack | `deploy-v2/m2/evidence/` (this TP's evidence list) |
