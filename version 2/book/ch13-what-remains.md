# Chapter 13 — What Remains

> **In plain terms.** A rebuild that claims success should also say what it
> did *not* do. This closing chapter states plainly what the `ea-` build
> demonstrated, what it deliberately deferred, and what comes next — in
> priority order, with the reasoning attached. It ends with the verdict the
> V2 record supports.

## 13.1 What the V2 build demonstrated

The staged build (M0–M5, 2026-11-13 → 2026-11-15) re-proved the
organization's defining guarantees *under a harder constraint than V1
faced*: the first system stayed up the whole time, on the same VMs, on the
same broker, against the same exchange. Each principle closes as
demonstrated again, with V2-specific evidence:

| Principle | Demonstrated by (V2 evidence) |
|---|---|
| Durable core | Temporal restart absorbed mid-gate (T5); TC-M2-04 crash recovery with the independent reaper; queue held 50 messages through a bridge kill with no loss |
| Ephemeral workforce | Zero survivors across every gate — 10/10 mixed runs, all five failure injections, every E2E acceptance run |
| Least privilege, provably brief | Per-run App tokens issued → authenticated → revoked → **401**, live in the §6 hardening stage; trivy secret scan 9/9 images clean |
| Institutional memory | End-to-end hydration from the fresh V2 store (single seeded entry — V1 rows absent, proving isolation); full curation cycle through the git-repo llm-wiki (D-wiki-git), with a fresh clone finding the new document |
| Judgment at the doors | The manager validated every task before publish; the single `x-max-priority` declaration point enforced the queue contract once, estate-wide |
| **Coexistence** *(V2's own addition)* | Two live organizations on one estate: V1's dashboards stayed 200 and its queues kept draining by its own bridge during every V2 gate; V2 routes never touched V1 queues (after the shared-exchange race was found and fixed — Chapter 12, entry 10's context) |

And the process claims are themselves demonstrated, not asserted: every
root cause in the ledger was caught by a gate or a byte-level check before
it could ship (findings §4.2); all six test procedures (TP-M0 … TP-M5)
signed all-PASS with filed evidence; the whole build ran in three days
against V1's four.

## 13.2 What was deliberately deferred

These are not failures. Each is a named boundary, carried in the decision
log with its reasoning — the same discipline as V1's deferred list, updated
by what the build learned:

1. **A+ isolation (the first post-build milestone candidate).** Workers
   remain co-located containers on the shared execution VM — level A of the
   isolation ladder. A+ (rootless runtime + egress allow-list, re-specified
   as segmentation + rootless, both gate-asserted) is designed and
   separately gated; the build deliberately shipped level A first because
   correctness is cheaper to prove than depth.
2. **The embeddings decision (D-embed).** No provider was staged; the
   zero-vector fallback runs (reads are q-driven and functional, semantic
   ranking is degenerate). Policy stays evidence-driven: a small
   self-hosted model on the memory VM only if pointer recall proves poor.
3. **Secure key management (D-secret-vault).** Owner-deferred. Secrets
   staged in gitignored 0600 files with rotation at every milestone gate —
   adequate for a private estate; a vault on the front-of-house VM is the
   named next step, not built.
4. **Concurrency beyond sequential.** The concurrency model is *locked* at
   one coder per task (TC-M5-05) with the manifest-configurable
   `max_parallel_agents` (default 5) decided as policy; N-parallel
   same-repo execution and the scope-declaration milestone remain future
   gated changes. Worktrees were evaluated and rejected (design §11).
5. **Umbrella compose.** No single compose file spans the estate. Bring-up
   after a reboot follows the documented dependency order (Chapter 14) —
   and everything now runs `restart: unless-stopped`, so the manual order
   is the fallback, not the norm. The umbrella remains unbuilt.
6. **Contract test suite as a standing artifact.** Conceived in the
   platform design (§9.2/§9.6) to run at every stage boundary; not yet a
   standing, runnable suite. Until it exists, the byte-level checks the
   gates actually ran are the precedent it will codify.
7. **Production hardening.** Unauthenticated dashboards, LAN-only
   perimeter, operator-level administration, pinned-runtime residuals —
   all inherited POC boundaries, all named. Two dependency refreshes
   (Claude Code CLI > 2.1.318, Hermes Agent > v0.23.0) would clear the
   accepted lang-pkg residuals; the trivy sweep records them honestly.
8. **The owner-side topology re-draw.** The ARCHITECTURE/foundation-doc
   diagrams are deliberately stale; the owner redraws them as a standing
   post-validation directive (the book leaves owner-drawn diagram slots
   for exactly this reason).

And one item is *next* rather than deferred: **the Chief-of-Staff milestone
(TP-V2-M1)** — the persistent resident agent between the desktop and the
unchanged gateway, the actual reason V2 exists. The staged build was its
prerequisite: the pipeline it will submit into is now proven, ea-named,
coexisting, and gated.

## 13.3 The next work, in priority order

Derived from the build's evidence and the deferred list above:

1. **TP-V2-M1 — the Chief-of-Staff milestone.** The capability V2 was
   built to unlock (natural-language intake, board-driven approval,
   multi-package work). Its prerequisites are now demonstrated baseline;
   its test procedure (assertions 1–12, judgment corpus as pre-gate eval)
   is already specified.
2. **A+ isolation** — the first post-build *change* milestone, gated:
   segmentation + rootless, re-verifying hydration and the credential
   capability checks under the new boundary.
3. **Dependency refreshes** — cheap, bounded, and they clear the two
   pinned-runtime residuals the hardening stage currently documents.
4. **Contract test suite as a standing artifact** — the process investment
   that makes every later change cheaper; it codifies the byte-level
   checks this build ran ad hoc into something re-runnable at every stage
   boundary.
5. **Umbrella compose** — one command for ordered bring-up; small, and it
   removes the last manual sequence from reboot recovery.
6. **Concurrency beyond sequential** — the scope-declaration milestone,
   gated, after the shared execution VM's capacity ceiling is measured by
   the soak-test gate (design §9.3) — especially before a second team
   onboards (the new-project runbook's shared-capacity note).
7. **The embeddings decision** — evidence-triggered, not scheduled: build
   it only if pointer recall proves poor.
8. **D-secret-vault** — security depth on the front-of-house VM, before
   any exposure or multi-team trust divergence.
9. **Production hardening** — transport, authentication, and identity for
   anything beyond the private network; the exit item before this stops
   being a POC.

The ordering is the same shape as V1's: capability that has already earned
its gate first (the CoS), then the gated change the evidence points at
(A+), then cheap hygiene, then process investment, then the
evidence-triggered and owner-deferred items. A roadmap that starts with
hardening before the core capability ships hardens a system nobody is
using yet.

## 13.4 The verdict

V1's verdict — *feasible: demonstrated, not merely argued* — was tested
again under a constraint V1 never faced: **can the organization be rebuilt,
from the record, beside a live copy of itself, without stopping it?** The
`ea-` build's evidence answers yes. Thirteen root-caused defects (Chapter
12), six signed gates, zero production incidents, and at the end of three
days two organizations were running on one estate — the predecessor
untouched, the rebuild fully gated, and the differences between them
reduced to one shared-exchange race found live and fixed at the publish
point.

> **The V2 verdict: the organization is not just buildable — it is
> *re-buildable and coexistable*.** The guarantees held under a harder test
> than the first build ran; the first build's rules visibly shrank the
> failure count; and the limitations are named, bounded, and scheduled —
> with the coexistence proof standing as the platform claim's first real
> data point: N systems per estate is no longer a design assertion.

The sentence this book exists to deliver, unchanged in substance and now
backed twice: **the gap between "an AI that talks about work" and "an
organization that does work accountably" is not a model problem. It is an
architecture problem — and it has now been solved, re-solved beside the
first solution, and written down both times.**

## 13.5 Where to go from here — for each reader

- **If you are the decision-maker:** the new fact since V1's book is
  §13.1's last row — the platform claim (many teams, one estate) has its
  first evidence, and the onboarding recipe exists (`deploy/RUNBOOK-V2-NEW-PROJECT.md`).
  The question is no longer "does this work?" but "which team goes
  second?"
- **If you are the architect:** Part II as rebuilt is the diff you would
  apply to V1's design: naming as a gated micro-gate, queue-direct
  publishing, the executor switch as a milestone responsibility,
  stage-gates that re-assert skipped preconditions. Chapter 12's five
  V2 rules are the ones to encode before your first *second* deployment.
- **If you are the skeptic:** the most falsifiable V2 claims are the
  coexistence ones — that V1's dashboards stayed green mid-build, that
  `ea-*` containers and V1's `poc-*`/`m*-*` containers ran side by side,
  that the takeover incident (one compose `name:`) was repaired and
  ruled against. Every gate's evidence pack is committed under
  `deploy-v2/mN/evidence/`; Chapter 15 tells you how to re-run the checks
  yourself against the live estate.

---

*The organization it describes is running — and so is its predecessor.*
