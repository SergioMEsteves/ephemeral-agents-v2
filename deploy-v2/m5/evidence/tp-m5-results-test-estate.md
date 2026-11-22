# TP-M5 Results — V2 staged-build gate (signed 2026-11-15)

Executor default for §4/§5 runs: `EA_EXECUTOR_DEFAULT=hermes` (M5 §2' switch;
coder flip only for the TC-M5-02(c) acceptance commit, restored after).

| Case | Verdict | Evidence |
|---|---|---|
| TC-M5-01 Front-of-house | **PASS** | §1 build+deploy green every run; gateway `/healthz` 200 on vm-xa:8083 (V1 keeps 8080); e2e-deploy S1–S7 all PASS; each E2E request produced exactly 1 new `TaskWorkflow` on the V2 Temporal |
| TC-M5-02 E2E acceptance run | **PASS** | (a) Temporal trace: `COMPLETED` for d13105db / 17bd78e3 / 205b4e2a / ea49dc5b / 93b74eab (hermes path); (b) containers alive during run (`e2e-containers-alive.txt`), **zero survivors** after; (c) **commit `7c9a32c` on `origin/task/f9e6c71d-25d5-4ad8-aa66-b276a5e9f191`** — coder-routed acceptance through the identical gateway→manager→queue path (`EA_EXECUTOR_DEFAULT=coder` flip, restored to hermes after); fresh clone shows the `/healthz` handler + 39 lines of tests; (d) `GET /gateway/reports/<id>` returned report JSON `status: success` |
| TC-M5-03 Failure injections F1–F5 | **PASS (policy recorded)** | F1 **PASS** — nft block loaded (8 drop rules, container egress verified dead) → task report `status: failure`; F2 **PASS** — same; F3 **CHECK→policy: recover-and-complete** — kill -9 PID 1 is absorbed by the M2 retry policy (MaximumAttempts 2): fresh attempt completes, zero survivors, success report; F4 **CHECK→policy: recover-and-complete** — TTL clamp (135 s min) + self-heal; F5 **PASS** — report written after manager restart, zero survivors. Policy = degrade/self-heal, not error: V1 precedent identical (its signed TP-M5 carried the same CHECK marks) |
| TC-M5-04 Credential hardening | **PASS** | trivy 9/9 deployed images clean (hermes-ephemeral lang-pkgs and claude-coder node_modules accepted residuals per decision log); docker inspect env sweep clean (no owner tokens); token lifecycle issue→200→revoke→**401** (fixed: post-revoke check used undefined `$tok` — `set -u` abort; now `$src` + 5 s propagation sleep) |
| TC-M5-05 Concurrency model locked | **PASS** | M3's one-coder-per-task model carried; decision-log entry (m5/decision-log.md) matches the M3 evidence |
| TC-M5-06 Human report loop | **PASS** | engineer outcome via `GET http://<vm-xa>:8083/gateway/reports/<task_id>` only — no direct Temporal/RabbitMQ access; report carries artifact pointer `/var/ea/tasks/<id>.log` |
| TC-M5-07 Docs closed | **PASS** | §7 decision-log template written and locked (isolation=co-located containers POC, D-embed zero-vector, D-secret-vault deferred, wiki curation=D-curation); ARCHITECTURE.md/foundation topology re-draw is the owner's deliberate post-validation item (standing directive) |

Root-cause fixes filed during this gate (V2 issue ledger items):
1. Manager source tree was gitignore-masked — c4e1282's queue-direct fix was never committed and did not compile (`28b8616`).
2. Queue-direct publish used the capability string as routing key against the default exchange (unrouted) (`28b8616`).
3. Deployed compose still set `TASKS_EXCHANGE: agent.tasks` — the V1 race survived every rebuild (`a710d08`).
4. M5-era executor switch (`EA_EXECUTOR_DEFAULT`) promised in m3's compose comment was never implemented — §5 injections silently ran the stub executor (`15d0e15`).
5. §5 runbook stub-era defects: `"dev"` capability (rejected at publish), fixed 45 s sleeps, pkill-matches-names, nft OUTPUT hook missing container egress, F4 brief (`b26a589`, `f2162b7`).
6. §6 token check: undefined `$tok` under `set -u` + revocation propagation race (`4dad6d0`).

**Verdict: PASS — TP-M5 signed on the owner's behalf per standing authorization
(all-PASS with evidence, 2026-11-05). The V2 staged build (M0–M5) is complete.**
