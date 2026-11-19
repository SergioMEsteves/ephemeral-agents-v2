# V2 Findings Report — the staged build, M0–M5

*The evidence record for the `ea-` build. Companion to the V2 book
(`version 2/book/`, in progress) and the V2 issue ledger
(`V2-issue-ledger.md`, 13 entries). Written 2026-11-15 from the committed
record; every claim traces to a filed evidence pack or a pushed commit.*

## 1. What was built

The staged build executed 2026-11-13 → 2026-11-15 across four VMs,
re-producing the baseline build's proof-of-concept under the `ea-` naming family with
the design decisions applied:

- **M0** — estate foundation: broker user `ea:`, `ea-tasks` family
  (`ea-tasks`, `ea-tasks.dlq`, `ea-tasks.response`) declared once with
  `x-max-priority: 3` (OQ4's single declaration point), temporal on
  `ea-net` (compose-declared, rabbitmq-pattern), Go-SDK smoke. All gates.
- **M1** — `ea/topic-bridge` consuming `ea-tasks`: T1 50→50, T3 kill-9,
  T4 poison→DLQ, T5 temporal-restart. TP-M1 6/6 PASS.
- **M2** — `ea/lifecycle` + `ea/worker`: V1–V5 green on the re-run,
  TC-M2-06 no-pull rule exercised separately. TP-M2 7/7 PASS.
- **M3** — executors `ea/hermes-ephemeral` + `ea/claude-coder`, per-run
  App-token issuance, boot p50 ≈ 1.4 s, coder commit on the demo repo,
  issue→revoke→401, zero trivy secrets. TP-M3 7/7 PASS.
- **M4** — memory: `ea-hindsight` on vm-hindsight :8082, own volume,
  end-to-end hydration, curation cycle via the llm-wiki git repo
  (D-wiki-git). TP-M4 7/7 PASS.
- **M5** — front-of-house `ea/gateway` (:8083) + `ea/manager` (:8086) on
  vm-xa; §4 E2E, §5 injections, §6 hardening, §7 docs closeout.
  TP-M5 PASS (7 mandatory cases; F3/F4 CHECK-with-recorded-policy).

Coexistence was the build's defining constraint: the first organization's stacks stayed up
on the same VMs throughout. The result — two live organizations on one
estate, V2 routes never touching the first organization's queues, its containers untouched —
is itself a finding (§4.1).

## 2. Gate results

| Milestone | Cases | Verdict | Signature |
|---|---|---|---|
| TP-M0 | all (incl. cross-VM publish, network matrix) | PASS | signed |
| TP-M1 | TC-M1-01…06 | PASS | signed |
| TP-M2 | TC-M2-01…07 | PASS | signed |
| TP-M3 | TC-M3-01…07 | PASS | signed |
| TP-M4 | TC-M4-01…07 | PASS | signed |
| TP-M5 | TC-M5-01…07 | PASS (F3/F4 policy-graded) | signed |

All signed on the owner's behalf under the standing authorization
(2026-11-05): complete only on all-PASS with evidence.

## 3. What the V2 build changed relative to the baseline build

1. **Naming is structural, not cosmetic.** The `ea-` rename
   (`ea-rename-mapping.md`) was executed as a gated micro-gate *before*
   the build, with digest-identity verification on the three
   registry-resident images and a single `x-max-priority` declaration
   point. Cost: it front-loaded the coexistence rules (compose project
   names, volume names, ports, labels) into a checklist that then held
   for five milestones — with one exception caught by the ledger
   (entry 8).
2. **Publishing is queue-direct.** V2's manager publishes to the
   `ea-tasks` queue via the default exchange (routing key = queue
   name). Rationale and evidence: both the first organization's and this build's bridges bound
   `agent.tasks.#` on the *shared* exchange and derived the same
   WorkflowId from `task_id` — first-start wins, so exchange-routed V2
   tasks were executed by the first organization's pipeline live (observed on the first M5
   E2E). Queue-direct removes the race at the publish point. Trade-off:
   capability-based topic routing is first-organization-only for now; fan-out by
   capability returns as a versioned message-v1 additive change
   (D-routing, recorded in `deploy-v2/m0/decision-log.md`).
3. **The executor switch is an M5 responsibility.** M2/M3 must run the
   stub (the M2/M3 gates prove lifecycle mechanics without agent
   logic); M5 flips `EA_EXECUTOR_DEFAULT=hermes` in a dedicated,
   idempotent, hard-failing stage (§2'). The failure mode this closes —
   injections silently exercising the stub — is ledger entry 11.
4. **The runbook is executor-aware.** Every §5 wait polls the report
   file; kills are by PID with a docker-kill fallback; the fault
   injection blocks the `forward` hook (container egress), not host
   `output`; the injected capability is a real catalog ref.
5. **Lessons pre-applied, and still earning new ones.** The thirteen
   V2 issue-ledger entries (§5 below) include four that the book
   predicted the *class* of (volume/env pairs, network attachment,
   tracked literals) and nine that were genuinely new.

## 4. Findings — what the build demonstrated

### 4.1 Coexistence is the cheapest isolation
The build never stopped the first organization. One compose `name:` difference was the
difference between coexistence and takeover (ledger 8). Every first-organization stack
was verifiable mid-build (its dashboards 200, its queues drained by its
own bridge). The organization-scale claim — N systems per estate —
got its first real data point.

### 4.2 The gate rule caught every major error before it shipped
Every root cause in §5 was caught by a gate or a byte-level check, not
by a production symptom: the gitignore source-masking was caught by the
m5 image build, the routing-key bug by re-reading the diff, the stub-
executor injection by the instrumented block-load log. The staged-build
process (§9.6) earned its cost: 13 ledger entries across 5 milestones,
each converted into a rule the next stage enforced.

### 4.3 Stage-gated runs have their own failure mode
`M5_FROM=5` re-runs were silent about the executor default they skipped
the stages that set. The fix (§2' re-asserts it on every invocation)
generalizes: **a stage gate must re-assert the preconditions the
skipped stages would have established**, not merely check that earlier
stages once passed.

### 4.4 Display masking is a debugging hazard
The terminal masks secret-like strings — which twice made a *correct*
file look broken (`$src`/`$tok` showing as `***`) and twice made a
*broken* file look fine. The rule now in force: verify file contents
by byte-level reads (python), never by display output (ledger 5, 13).

### 4.5 Executor-vs-stub is observable and assertable
The stub sleeps its TTL and reports success; hermes boots in ~1.4 s,
hydrates three files, runs minutes, and either produces the artifact
or a failure-shaped report. Because the two are behaviorally distinct
in exactly the ways the gates check, the executor must be asserted by
name in any test whose verdict depends on it (ledger 11).

## 5. What remains (from §7 of M5, per the decision log)

- Owner-side: ARCHITECTURE.md / foundation-doc topology re-draw
  (owner-directed; the old diagrams are deliberately stale).
- Deferred topics carried: secure key management (D-secret-vault),
  embeddings provider, isolation ladder A+ (post-M1 gated change),
  concurrency beyond sequential, umbrella compose, contract test suite
  as a standing artifact, production hardening.
- The A+ isolation upgrade is the first post-build milestone candidate.
- Dependency refreshes (Claude Code CLI > 2.1.318, Hermes Agent >
  v0.23.0) to clear the pinned-runtime residuals.

## 6. Commits of record

`d2afc5d` (rename micro-gate) · `1f98b82` (m0) · `2c5cedf` (m1) ·
m2/m3/m4 commits in WORKING-STATE ninth–eleventh updates · `c4e1282`
(m5 transform — superseded) · `28b8616` `a710d08` `0aa671c` `b26a589`
`f2162b7` `15d0e15` `cb217f3` `4dad6d0` `fb065bc` (m5 completion).
Estate evidence: `deploy-v2/mN/evidence/` per milestone.
