# TP-M1 — M1 Adapter Test Procedure results (V2, ea-)

**Date:** 2026-11-14 · **Estate:** V2 (ea-), coexistence with V1 (/opt/poc) untouched
**DUT:** `ea/topic-bridge:1.0.0` — compose project `ea-m1`, container `ea-m1-topic-bridge-1`, vm-xb
**Companion:** `deploy-v2/m1/evidence/m1-tests.txt` (T1–T5 run), `install-m1.log`

## Mandatory cases

| ID | Case | Result | Evidence |
|---|---|---|---|
| TC-M1-01 | Poison-pill → DLQ | **PASS** | T4: 3 invalid messages routed to `ea-tasks.dlq` with reason property; consumer still up; `ea-tasks` depth 0. DLQ sample: header `x-reject-reason: "missing required field \"agent_ref\""` (see `m1-dlq-sample.json`) |
| TC-M1-02 | N → N (N=50) | **PASS** | T1: +50 workflows started (exact +50) |
| TC-M1-03 | Duplicate idempotency | **PASS** | T2: +0 new workflows on 50 duplicate task_ids (WorkflowID=task_id contract holds) |
| TC-M1-04 | Kill -9, no loss | **PASS** | T3: `docker kill` + `docker start` on `ea-m1-topic-bridge-1` mid-flight; +20 redelivered, no doubles |
| TC-M1-05 | Temporal restart recovery | **PASS** | T5: temporal restart + 30 s; consumer reconnected automatically; +5 workflows |
| TC-M1-06 | Rollback / re-deploy | **PASS** | `docker compose down` + `up -d`; 5 messages published while bridge down → durable queue held 5, drained to 0 on restart, consumer reconnected (1), 5 new TaskWorkflows running |

## Informational

| ID | Note |
|---|---|
| I-M1-01 | Throughput: 50-message burst consumed within the 5 s T1 window (gate run) |
| I-M1-02 | Log hygiene: json-file rotation caps (10m × 3) configured in compose.yaml; no unbounded growth during the run |

## Environment notes

- V2 bridge consumes `ea-tasks`/`ea-tasks.dlq` (queue family declared with x-max-priority: 3 in m0); V1 bridge (`m1-topic-bridge-1`) untouched, still consuming `agent.tasks.durable`/`agent.tasks.dlq` — coexistence clean, `agent.tasks.dlq` = 0 throughout the run.
- All adapter code Go (language decision): `go vet` + `go build` + tests green; binary Go-verified in the image (install §2).

## Gate decision

**PASS** — TC-M1-01…06 all PASS → **M2 installation authorized**.

## Sign-off (D-signoff, 2026-11-04)

Signed on owner's behalf per standing authorization (2026-11-05): all-PASS with evidence filed.

| Field | Value |
|---|---|
| Signed by (HITL) | Owner (delegated to Hermes, standing authorization) |
| Date | 2026-11-14 |
| Evidence pack | `deploy-v2/m1/evidence/` (m1-tests.txt, m1-dlq-sample.json, tp-m1-results.md) |
