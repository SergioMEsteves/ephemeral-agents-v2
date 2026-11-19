# V2 Gap Analysis — pre-build declaration (2026-11-11)

> Companion to the feasibility study (`V2-feasibility-study.md`). Answers
> one question: **what is still missing between where the project is today
> and a declared, useful, successful V2?** Every gap is classified
> (none is currently a build blocker — the pre-build gate is otherwise
> green), with its owner and the point in the build where it closes.

## 1. Gap classes used

- **[B]** Build blocker for M1 — must close before/at the M1 build.
- **[G]** Gate-blocker — must close before TP-V2-M1 can be signed.
- **[P]** Post-M1 gap — lands with a later, separately-gated milestone.
- **[D]** Deliberate deferral — owner-decided; a feature, not an omission.

## 2. Design → implementation gaps (code exists, unproven at runtime)

| # | Gap | Class | Owner / closes at |
|---|---|---|---|
| G-1 | The CoS itself has never run: the Hermes profile (persona hydration, board, approval loop) exists only in design + the ported code path. Nothing yet proves a real proposal→approval→submission round. | **[B]** | M1 build stage 6 (CoS profile) + TP-V2-M1 |
| G-2 | The two-tier work board (ADR-0001) is designed but unbuilt: no tracker exporter, no local board init, no board/queue reconciliation code. | **[B]** | M1 build; TP assertion 9 exercises it |
| G-3 | Desktop↔gateway registry connection (session-token auth, reconnection) — specified (M1 §3), not implemented on the workstation side. | **[B]** | M1 build; TP assertion 12 |
| G-4 | Go services ported ea-named and unit-tested locally, but **not built as images, not deployed, not integration-tested on the estate**. Harness-verified ≠ integration-verified (lesson 4). | **[B]** | staged build (chassis → smoke) |
| G-5 | The M1 manager changes (priority validation, approval-hash ledger) are unit-tested pure logic; the wiring into the manager's publish path (where retries actually happen) is minimal — the retry path integration test does not exist yet. | **[G]** | contract suite extension + TP assertions 2/10 |
| G-6 | `deploy-v2/rename-to-ea.sh` staged, never run: registry re-tag by digest, `ea-tasks` queue with `x-max-priority`, baseline re-run. Estate untouched. | **[B]** | declare-start, first estate session |
| G-7 | Executor images still carry V1 registry names; digest-pinned pulls (`ea/…@sha256:…`) with lifecycle re-verification are designed, not implemented in the spawn path. | **[G]** | build-start security stage |

## 3. Estate-readiness gaps (per PREBUILD-CHECKLIST.md, all owner-executed at declare-start)

| # | Gap | Class |
|---|---|---|
| G-8 | Reboot-orphaned containers from the 2026-11-10 cleanup: stacks not yet brought back up; current estate health unverified. | **[B]** |
| G-9 | Registry VM still tag-pinned + unauthenticated `:5000` (TLS + basic auth + GC policy designed, not applied). | **[B]** |
| G-10 | New secrets (registry basic-auth, llm-proxy class tokens, Hindsight write/read split) not yet staged anywhere — templates and staging locations defined, values nonexistent. | **[B]** |
| G-11 | Memory VM: Hindsight token split + Proxmox firewall restriction of `:8081` to VM-Xa/VM-Xb not applied. | **[G]** (assertion 6 adjacency) |
| G-12 | Chassis inventory not re-verified against reality (lesson 10: the "moving floor" check happens at build start). | **[B]** |

## 4. Process / record gaps

| # | Gap | Class |
|---|---|---|
| G-13 | The V2 issue ledger (§9.6 full V1-style build process record) does not exist yet — it is a build-phase artifact that must be created on day one of the build. | **[B]** |
| G-14 | Contract test suite covers 3 boundaries (message-v1, catalog, spawn-env); the remaining V1 per-milestone scripts are not yet folded in (queue declare shape, report contract, credential-revocation timing). | **[G]** — grows with milestones |
| G-15 | No CI (documented manual corpus re-run rule); accepted at M1. | **[D]** → queue item 8 |
| G-16 | Capacity model + soak test (§9.3) designed, not measured — concurrency default 5 is a design number, not an evidence number. | **[P]** — post-M1 gate |
| G-17 | V2 demo repo + GitHub App install don't exist (needed only when coder-style work arrives). | **[D]** |
| G-18 | Key vault (D-secret-vault) owner-deferred; secrets temporarily homeless in 0600 gitignored envs — acceptable, documented rotation expectation. | **[D]** |
| G-19 | Isolation ladder A+ (rootless runtime + egress allow-list) not built — a post-M1 gated milestone by decision. | **[D]** → A+ gate |
| G-20 | V2 book + findings report: closing deliverables by owner decision (written after full deployment is proven). | **[D]** |

## 5. Design documents — no open gaps

All five third-pass review conditions are applied and committed; OQ1/OQ4
closed; ADR-0001 recorded; the impact inventory + endpoint table, rename
mapping, judgment corpus, contract suite, rename script, and security
staging templates are written and verified (commits `d2afc5d`…`2963101`).
No unresolved finding remains from any of the three design-review passes.

## 6. Verdict

**No unknown gaps remain.** Every open item above is enumerated, classified,
and owned by a named build stage or a recorded owner decision. The gap
between today and "build start" is exactly: G-6 + G-8…G-13 (one estate
session's work, all scripted or checklist-driven) plus G-1…G-3 (the M1
build itself, which is the milestone). Nothing discovered so far suggests
a missing design decision; the residual risk is execution, not conception.
