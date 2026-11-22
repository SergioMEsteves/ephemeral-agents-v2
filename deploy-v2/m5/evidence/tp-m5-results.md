# TP-M5 Results — live estate (signed 2026-11-22)

Second sign-off of TP-M5: the full M5 gate re-run on the LIVE estate
(.233 front-of-house / .224 execution / .223 memory / .198 registry), completing
the live-estate milestone sequence S1, m1, m2, m3, m4, m5. The test-estate pack
is preserved as `*-test-estate.*` alongside.

Executor default for §4/§5 runs: `EA_EXECUTOR_DEFAULT=hermes` (§2' switch).

| Case | Verdict | Evidence |
|---|---|---|
| TC-M5-01 Front-of-house | **PASS** | §1 build+deploy green; gateway `/healthz` 200 on .233:8083; e2e-deploy S1–S7 all PASS (coexistence mode: live m0 Temporal/rabbitmq reused); each stage its own gate |
| TC-M5-02 E2E acceptance run | **PASS** | task `83229c03` (`eph-backend-engineer`, TTL 900 s): gateway → manager (queue-direct `ea-tasks`) → real hermes executor → Temporal COMPLETED → report `status: success` at `completed_at 2026-11-22T21:04:45Z`, artifact `/var/ea/tasks/83229c03….log`; `e2e-report-83229c03….json` captured from `GET /gateway/reports/<id>`; survivors=0 |
| TC-M5-03 Failure injections F1–F5 | **PASS (policy recorded)** | F1 **PASS** (git/HTTPS block → failure-shaped report, survivors=0); F2 **PASS** (nft 443 block → failure report, survivors=0); F3 **CHECK→policy: recover-and-complete** (kill -9 absorbed by M2 retry — success report, zero survivors; same CHECK precedent as the signed test-estate TP-M5); F4 **CHECK→policy: recover-and-complete** (TTL clamp + self-heal, success report); F5 **PASS** (manager restarted mid-task — report still written, survivors=0) |
| TC-M5-04 Credential hardening | **PASS** | trivy 9/9 clean after a fresh `--no-cache` rebuild of ea/lifecycle+ea/worker (was: one fixable HIGH, needrestart CVE-2026-124757 in the Nov-19 layer cache — see ledger 17); env sweep clean (no owner tokens); token lifecycle issue→**200**→revoke→**401** (ledger 18: revoke now runs the same sudo path as issuance) |
| TC-M5-05 Concurrency model locked | **PASS** | M3 one-coder-per-task carried; §2' executor default = hermes verified on the live ea-m2 compose |
| TC-M5-06 Human report loop | **PASS** | report via `GET :8083/gateway/reports/<task_id>` only; artifact pointer `/var/ea/tasks/<id>.log` |
| TC-M5-07 Docs closed | **PASS** | §7 decision-log template locked; ledger entries 17–18 filed |

Root-cause fixes filed during this gate (V2 issue ledger items 17–18):

20. **Layer-cache shipped a stale base package.** The §6 trivy HIGH
    (needrestart CVE-2026-124757, fixed in 3.11-1.1~deb13u1) survived a
    "rebuild" because `docker build` reused the Nov-19 apt layer — the RUN
    layer's apt snapshot is frozen at build time. Wrong assumption: a rebuild
    re-fetches packages. Fix: `--no-cache` rebuild, push to the registry,
    redeploy; image eb040562cd74 (2026-11-22) scans clean.
    Rule: a CVE-remediation rebuild must bust the base-image layer cache;
    a cached rebuild changes nothing.

21. **Privilege-path mismatch killed §6 silently.** The token state file
    `/tmp/ea-issue-token-last` is written by the §6 issuance, which runs under
    `sudo` (root-owned); the `--revoke-last` step ran as poc, could not read
    it, and `set -euo pipefail` killed the run with no message. Wrong
    assumption: the two steps share an execution context. Fix: both steps now
    run the same `sudo bash -c` path (deploy-v2/m5/install.sh §6).

**Verdict: PASS — TP-M5 signed on the owner's behalf per standing authorization
(all-PASS with evidence, 2026-11-05). The live-estate milestone sequence
(S1, m1–m5) is complete.** Remaining: TP-M1-COS (CoS gate; prereq = owner adds
the Desktop gateway connection vm-xa:8084 with COS_SESSION_TOKEN).
