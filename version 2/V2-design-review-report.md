# V2 Design — End-to-End Review Report (Second Pass)

*Date: 2026-11-10. Scope: the amended V2 design set — `V2-M1-cos-design.md`
(DRAFT v2, amended), `V2-platform-design.md` (DRAFT v1, amended), decision
log, WORKING-STATE, `schemas/message-v1.json`, README. Method: two
independent expert panels — (1) enterprise architecture + software
engineering + testability + internal consistency; (2) network engineering +
security architecture + SRE. This is the re-review after the first review's
28 findings were accepted by the owner and applied. Analysis persisted with
the owner's direction.*

## 1. Verdict: **READY-WITH-CONDITIONS**

The first review's closures are genuinely applied; no owner-decided item
was reopened by either panel. However, both panels **independently found a
critical contradiction introduced by the amendments themselves**, and a set
of conditions must be resolved before the build gate opens and TP-V2-M1 is
signed.

## 2. Closure verification (first review → amended docs)

| First-review area | Where | Status |
|---|---|---|
| Schema-evolution mechanics corrected | platform §5 | **Closed** — "exemplary: names the contradiction, states the mechanics, binds field+consumer to one gate" |
| Failure behaviors completed | M1 §6 | **Closed** — "a genuine decision table a TP can execute directly" |
| Manager changes enumerated per milestone | M1 §4 | **Closed** (one gap: manifest check has no owning gate assertion — §5.3) |
| Platform §9 build-phase plan | platform §9.1–9.7 | **Closed** |
| CoS state persistence mechanism | M1 §6.8 | **Partial** — specified, but contradicts §5's credential denial (§3.1) and has an unspecified push-race convention (§3.2) |
| Gate assertions 9–12 + judgment corpus | M1 §7 | **Partial** — present, but assertion 11 untestable at M1 (§3.4), assertion 10 has no verifier owner (§3.5), corpus not runnable as defined (§3.6) |
| Registry TLS + digest pinning | §9.1.1 | **Closed** (credential distribution + GC retention sub-gaps — §5) |
| llm-proxy caller auth + spend caps | §9.1.2 | **Closed** (class-token conflation of auth with attribution — §5) |
| Hindsight token + reach restriction | §9.1.3 | **Closed** (but new interactions with A+ segmentation and write-scope — §3.7, §3.8) |
| Dashboard publisher-identity control | §9.1.4 | **Closed** (choice deferred to build start, by design) |
| GitHub App token custody | §9.1.5 | **Closed** |
| A+ = segmentation + rootless, both asserted | §9.2 | **Closed** (but segmentation severs the memory-hydration contract — §3.7) |
| Capacity model + soak test + OOM kill-order | §9.3 | **Closed** |
| CoS observability minimum | §9.3 | **Closed** (gateway-log provenance ambiguity — §5) |
| Credential capability assertion + honesty note | M1 §5/§7.11 | **Closed as text; broken as a gate** (§3.4) |
| Prompt-injection compensations | M1 §6/§7.9–10 | **Closed** (residuals named in §6) |
| Rename ordering + micro-gate | §9.7 | **Closed** (grep-scope whitelist note — §5) |
| Pointer caveat / file-level inventory / build process | §2, §9.5, §9.6 | **Closed** (endpoint-level inventory missing — §5) |

## 3. Critical finding (convergent — both panels)

**3.1 CRITICAL — `cos-state/state.json` contradicts the CoS credential
contract.** M1 §6.8 requires the CoS to commit state to the project repo at
every transition and to read the repo as source of truth (manifest,
committed artifacts, the D10 results loop). M1 §5 **explicitly denies the
CoS any GitHub token**. As amended, the state-persistence mechanism, the
recovery mechanism, and the results loop are unimplementable without
violating the strict contract — the two provisions were amended in
different passes and never reconciled. **Owner decision required, two
options:** (a) grant the VM-Xa CoS profile a narrowly-scoped, content-
limited repo credential (e.g. `cos-state/*` + read) and amend §5 and
assertion 6's negative env list accordingly; or (b) keep state out of the
repo — a local persistent volume on VM-Xa plus a Hindsight pointer —
accepting the visibility/backup cost and restating §6.8's source-of-truth
claim. Either is viable; the contract must become internally consistent
before TP-V2-M1 is signed.

## 4. Major findings (new or exposed by the amendments)

1. **State push race (software):** the CoS commits `state.json` to the same
   repo executors push to; interleaved pushes non-fast-forward, and
   conflict semantics for machine-written JSON are undefined. → Fix: state
   on a dedicated `cos-state` branch executors never touch (or an
   explicit rebase-retry rule), exercisable in the TP.
2. **Assertion 11 asserts an enforcement that does not exist at M1
   (both panels):** §5 honestly defers capability enforcement to the
   post-M1 A+ rung, yet §7.11 lists the broker/manager-connection-must-
   FAIL check as a strict TP-V2-M1 assertion. At rung A it would pass by
   nothing — or fail the gate. → Fix: mark assertion 11
   conditional/deferred to the A+ gate (mirroring assertion 3's OQ4
   treatment), or specify the M1 enforcement primitive that makes it true.
3. **Hash-pinned approval has no verifier owner (enterprise):** §7.10 does
   not say *who* verifies the hash; the CoS is the untrusted party and
   cannot verify itself; the gateway is declared unchanged; the manager
   enumeration (§4) lists no approval-hash check; `state.json` hashes are
   CoS-written and cannot be the trust anchor. → Fix: name the verifier
   (the manager is the natural fit — added to §4's enumeration as its own
   gated change), define hash canonicalization, and specify the mismatch
   path (reject + notify owner).
4. **Assertion 2 not OQ4-conditional (internal consistency):** if OQ4
   defers the priority field, assertion 2's pass-through clause cannot
   pass, but only assertion 3 carries the conditional marker — a
   deferred-priority M1 gate is structurally unpassable. → Fix: extend the
   conditional marking to assertion 2's priority clause (and the
   contract-suite's priority cases).
5. **A+ segmentation severs memory hydration (network):** §2.4's hydration
   contract has executors reading Hindsight `:8081`; §9.2's A+
   allow-list is "registry, llm-proxy, github.com only." Both cannot
   hold. → Fix at A+ design time: add memory API (read-only) to the
   forwarder allow-list, **or** move hydration spawn-side (lifecycle
   pre-fetches and mounts the memory bundle) — the stronger isolation,
   and consistent with pointers-only anyway. Decision recorded now, rides
   the A+ milestone.
6. **Shared Hindsight token gives executors write access (security):** one
   token for CoS writes and executor reads means any compromised executor
   can poison memory pointers the CoS later reads as trusted context — an
   injection channel into the agent the prompt-injection findings
   hardened. → Fix: two tokens (CoS write / executor read-only) or a
   write-proxy on the memory VM; cheap, same gated item as §9.1.3.
7. **Judgment corpus not yet runnable (testability):** coverage dimensions
   are named but not storage location, cardinality, output format, scoring
   method, pass threshold, or the re-run trigger mechanism. → Fix: define
   it as committed fixtures with machine-checkable fields (agent_ref,
   priority class, DAG edges, additive/corrective label) plus an
   explicitly non-asserted judgmental remainder; name the location and
   trigger.

## 5. Minor findings and observations (fix in the next doc pass)

- **New secrets created by §9.1 have no home** — registry basic-auth
  credentials, llm-proxy tokens, and the Hindsight token all come into
  existence without a stated storage/rotation location (the vault is
  owner-deferred; their staging must still be specified — fold into the
  §9.1 gated items).
- **llm-proxy class-token conflates authentication with attribution** —
  add per-container task-id attribution headers (lifecycle-injected) with
  per-container rate caps, so spend anomalies are attributable to a task.
- **Dashboard HMAC is an unstated schema-evolution event** if done
  in-band — the build-start choice must be told which option carries which
  change surface (schema + worker, per platform §5's corrected rule).
- **`repo_target`-vs-manifest check has no owning gate assertion** and no
  defined manifest milestone — fold into assertion 2 with a conditional
  marker or record the milestone in the open-items queue.
- **Assertion 12's waiver** ("scoped out with rationale") should be
  explicit: the pass artifact is the written scoping decision itself.
- **Registry GC/retention policy** still absent (carried residual) — one
  line in §9.1.1.
- **§9.5 inventory is file-level only** — add the endpoint/flow table
  (component → outbound endpoints → port → auth → why) to its minimum
  coverage; it is also the verification artifact for §4.5/§4.6.
- **CoS model-key path ambiguity** — state explicitly that CoS LLM calls
  go through llm-proxy with the CoS-class token, so spend caps cover the
  highest-spend actor.
- **`state.json` content sensitivity + crash-consistency** — task ids,
  gateway errors, approval hashes in the project repo (private today;
  not guaranteed private for future projects); recovery on unparseable
  state must fail safe to no-submit and surface to the owner.
- **Gateway audit-log provenance** — if V1's gateway already emits
  sufficient submit logs, cite it; otherwise it is a gateway change and
  must be enumerated like the manager changes in §4.
- **Doc drift:** WORKING-STATE "Next actions" still lists the pre-review
  TP assertion set and omits the rename+inventory build opening; umbrella
  compose and contract-test-suite queue items are subsumed by §9.2/§9.6
  but still listed open; stale cross-reference in platform §1 (runtime
  choice points at the TP section, not the manifest §10); the
  grep-scope/mapping-table whitelist for the rename micro-gate needs
  defining; the A+ allow-list forwarder is a monitored single point of
  failure, and digest bumps are part of the dependency-refresh cycle.
- **Record reconciliation:** the first review is recorded once as 28
  findings (4 critical / 10 major / 9 minor / 5 observation) — the sum of
  both panels; this report's closure table tracks them by area.

## 6. Residuals (accepted or deferred — standing, not reopened)

Key vault (owner-deferred); true cancellation (D10, separately gated);
file-scope declaration + manager exclusion (later milestone); model
specification & configurables (reset topic); Hindsight per-project scoping
and per-project token lifecycle (at second project); embeddings provider
(evidence-triggered); UI-publish control choice (build start);
session-transcript retention period; prompt-injection soft residuals
(persona-level untrusted-content rules, CoS-local void enforcement — the
human approval loop remains the real control at M1; recorded as accepted
residuals of rung A/M1, and the watch-item for isolation rung B).

## 7. Strengths of the amended design (both panels)

1. The schema-evolution correction is exemplary — mechanically true, not
   aspirational, and the manager enumeration matches it.
2. Failure behaviors are an unusually complete decision table, gate-backed.
3. The two-piece A+ split prevents "rootless-swap-theater" passing as
   segmentation; the ladder's written tripwires remain standing policy.
4. Capacity-before-trust with encoded OOM kill-order is the right SRE
   instinct; CoS observability is minimum-viable and honest.
5. The build-phase commitments (file-level inventory asserted against by
   every gate, V2 issue ledger, book-last) structurally close the V1
   "moving floor" and paper-over classes of problem.
6. Decision hygiene remains exemplary — "decided" is distinguishable from
   "defaulted" everywhere in the record.

## 8. Conditions before the build gate opens

1. **Resolve §3.1** — the CoS repo-credential contradiction (owner
   decision, option a or b; contract text made internally consistent).
2. **Reconcile assertions 2/3/10/11** — OQ4-conditionals complete; the
   approval-hash verifier named and enumerated as a gated manager change;
   assertion 11 marked conditional/deferred to A+.
3. **Record the A+ memory-hydration and Hindsight-token decisions** (§4.5,
   §4.6 paths chosen — implementation rides A+).
4. **Fix the doc-drift list** (§5) in one pass, including WORKING-STATE's
   next-actions and the subsumed queue items.

Once these four are applied, the design is **ready to build**.
