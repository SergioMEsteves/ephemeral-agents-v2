# V2-M1 — Chief-of-Staff Agent Design

*Status: DRAFT v2, in active design discussion with the owner (2026-11-09).
Supersedes draft v1; the v1 bespoke-HTTP-API connection design is recorded in
§9 as a rejected alternative.*

## 1. Goal

A persistent resident **Hermes Agent** — the bus-org **chief-of-staff** persona
— runs on the front-of-house VM ("VM-Xa"; from 2026-11-09 the term means any
VM with a Hermes Agent deployed) between the gateway and the manager —
the gateway is unchanged in M1, and the manager is touched only by its
enumerated, individually gated changes (§4; wording corrected per the
third-pass drift pass, since "unchanged" stopped being true with D8 and
the approval-hash check). The owner talks to the CoS conversationally from the
Hermes Desktop; the CoS decomposes the request into proposed work packages;
the owner approves; the CoS submits through the gateway API; the manager
validates as it does today; ephemeral executors run; reports flow back.

**The agent proposes, the code disposes.** The CoS holds no authority the
manager does not already enforce.

## 2. Decided (owner, 2026-11-09)

| # | Question | Decision |
|---|----------|----------|
| Q1 | desktop ↔ CoS connection | **Native Hermes Desktop gateway registry.** The desktop registers the VM-Xa Hermes gateway as a named remote connection (session-token auth). No bespoke CoS HTTP API. Supersedes draft v1's custom-API decision. |
| Q2 | approval mode | **Ask-before-submit**: CoS proposes the decomposition, owner approves, then it submits. Autonomous mode is a later, separately-gated change. |
| D3 | CoS runtime | The CoS is a **Hermes profile on the VM-Xa gateway** (long-lived Hermes Agent instance, CoS persona), not a hand-rolled service imitating one. |
| D4 | Project source of truth | The **git repository the VM-Xa agent works from** — not the desktop. The desktop holds no project state. |
| D5 | Desktop role | Thin window: converse, research (thinking layer), consolidate, hand off, receive results. The desktop MAY upload files/data into the VM-Xa session; it never holds project context. |
| D6 | Multi-project | One project = one VM-Xa = one gateway = one resident CoS. The desktop registers N gateways (one per project) simultaneously; projects are isolated by default (separate CoS instance, memory, sessions). No shared CoS across projects. |
| D7 | CoS management model | The CoS operates as a manager of people: (a) selects the best-fit agent from the roster for each task; (b) maintains a working backlog in its own session state and decides order and parallelism; (c) handles change requests arriving mid-flight; (d) escalates to the owner with exact, clear questions when its judgment is insufficient — ask-or-proceed, never guess-and-fire. |
| D8 | Prioritization | The CoS **declares** priority in the work package (new optional `priority` field in message-v1); the **manager validates and applies** it; RabbitMQ per-message priority and/or Temporal task-queue priority enforces pickup order. The CoS never touches the broker. *OQ1 closed (owner, 2026-11-10):* the encoding is **coarse — `high` / `normal` / `low`** (an enum; out-of-range values are rejected outright). Rationale: the declarer is an LLM — a 1–10 scale would carry precision the judgment source doesn't have; three levels survive judgment, make declare-everything-high visible and auditable, and map cleanly onto RabbitMQ `x-max-priority` / Temporal priorities. Finer ordering stays in the CoS's own backlog sequence and submission timing — where fine-grained ordering belongs (judgment, applied through submission order). |
| D9 | Parallelism | Independent packages are submitted concurrently and run in parallel (pipeline already supports this). Dependent packages are held by the CoS until the upstream report returns. |
| D10 | Change management | No mid-flight interruption of ephemeral agents. New information arriving while a task runs is classified: **additive** (held for future packages) or **corrective** (a follow-on revision package issued after the in-flight task completes, referencing its artifact). The CoS reads results via the gateway report and/or the project repo, then composes follow-on work. True cancellation of in-flight runs is a separately-designed later milestone (it moves an enforcement action into judgment's hands). |
| D11 | Conversation boundary | Gateway → manager → queue unchanged; the CoS is a client of the gateway, nothing more. |
| D12 | CoS work board (owner, 2026-11-10) | The CoS maintains its work state on its **native Hermes kanban board** — one board per project CoS. Card = work package (agent_ref, behavioral_spec, priority, ttl); columns = proposed → owner-approved → submitted → in-flight → reported → rolled up, with corrective follow-ons as linked cards. The board is the CoS's **state store of record** (backlog, ordering, dependencies, held additive info) — replacing the earlier `cos-state/state.json` proposal, which would have required the CoS to push to GitHub in violation of §5. **The board is the CoS's desk, never the door:** the queue (RabbitMQ/Temporal) remains the only execution truth; a card moves to "submitted" only through the approval flow (gateway → manager validation); a card moving to "in-flight" is a *reflection* of the queue's truth, never the cause of it. Report events flow back to move cards. Board history doubles as the submit-side audit trail (observability minimum). |
| D12-rev | Two-tier work board (owner, 2026-11-10) | D12 revised: the work state is **two-tier**. **Tier 1 — the master plan** lives in an **external tracker** (GitHub Issues by default; ADO/Jira swap-in via a tracker-agnostic exporter): the CoS decomposes the behavioral specification into the complete plan — every intended work package — and the exporter (holding the tracker credential, staged gitignored per §9.1) publishes it. The master plan is the **plan of record**: durable off VM-Xa by definition, human-reviewable in the approval flow (the owner reviews the decomposition in the tracker), and the intent audit trail. **Tier 2 — the working set** is the CoS's local Hermes board: the CoS **pulls a logical subset** of master-plan items (unblocked, priority-ordered, within the 5-agent window and dependency rules) and drives that subset through the approval → submit → report loop. **Direction of truth per tier:** the tracker is authoritative for the *plan*; the gateway/manager/queue remain authoritative for *execution*; the local board is a working cache between them. Status flows up (local transitions → tracker status updates via the exporter); plan content flows down only via an explicit subset-pull. **Credentials stay out of the CoS** — the exporter holds the tracker key, never the CoS. If the tracker is unreachable the CoS works locally and syncs when it returns (offline-tolerant). The desk-never-door rule is unchanged: neither board can start work; only the approval flow → gateway → manager can. Rationale and alternatives: `adr-0001-cos-work-board.md`. |

## 3. Connection procedure (Q1 — native gateway link)

- The VM-Xa Hermes Agent runs its **gateway**; the Hermes Desktop adds it on
  Settings → Gateways as a named **remote gateway** connection (LAN HTTP(S),
  session-token auth) — the documented multi-connection desktop capability.
- Multiple project VMs each register as their own named connection; all are
  live simultaneously; the user switches conversations to pick a project.
- **Auth:** per-connection gateway session token, generated at VM-Xa setup,
  stored gitignored on both ends. The desktop holds no other credential for
  the project (no GitHub token, no queue access) — the native connection
  auth *is* the credential contract's inbound half.
- The CoS persona is loaded by the VM-Xa Hermes profile (skills/AGENTS.md +
  roster repo as project context) — configuration, not custom code.

## 4. Runtime shape

- **VM-Xa Hermes Agent** as a long-lived gateway-backed instance
  (`restart: unless-stopped`, reboot-safe per book ch14 §14.8).
- **Project context from the repo**: the agent's workspace is the project git
  repo checkout; project docs (e.g., a BSD), decision records, and working
  state live there. The repo is the single source of truth (D4).
- **Hydration** (the contract gains its first persistent consumer):
  persona files from the roster repo (`bus-org/chief-of-staff/`), llm-wiki,
  Hindsight (per-project scope; projects share nothing by default).
- **Gateway untouched.** Manager changes are enumerated **per milestone**
  (corrected per the 2026-11-10 design review — the earlier "single
  deliberate change" claim was inaccurate): (M1) the `priority` field
  validation + pass-through; (M1) **approval-hash verification** — the
  manager enforces retry integrity (identical spec hash across retries of
  the same `task_id`) and mismatch-reject-and-surface, via the
  `approval_hash` message-v1 field landing in this same gated change
  (tamper-evidence; see §7.10 for the honest limit and the later
  gateway-side enforcement upgrade); (M1 or the manifest milestone) the
  `repo_target`-vs-manifest check (§10, gated with whichever milestone
  carries it); (later scope-declaration milestone) the file-scope
  exclusion check (§11). Each is its own individually gated change.

## 5. Credential contract (strict)

The VM-Xa CoS profile receives exactly the following **enumerated
allow-list** (restated per the third-pass review — later decisions added
credentials the original three-item list did not include, and a conforming
build must pass assertion 6):

1. **Model access via the llm-proxy CoS-class token** — the CoS's LLM
   calls route through the llm-proxy, which holds the provider key on the
   CoS's behalf; the CoS holds no provider key itself. This places the
   highest-spend actor inside the proxy's spend-cap and logging
   perimeter (platform §9.1.2).
2. **Gateway session token** (inbound, for the desktop connection) — D3/§3.
3. **Gateway API credential** — to submit approved tasks; ordinary gateway
   client scope.
4. **Hindsight write token** — the CoS is the memory system's writer (the
   pointer-store convention, platform §2): after each report lands it
   writes the pointer entry. Executors hold the *read-only* token class;
   the write token is CoS-only (platform §9.1.3).

The **kanban board is not a credential** — it is native profile state on
VM-Xa (D12); the CoS needs no key to use it, which is precisely why the
board (not the repo) is the state store of record.

Explicitly **denied**: no GitHub token (the board removed the last reason
the CoS would need one), no queue (RabbitMQ/Temporal) access, no direct
manager access beyond the gateway API, no registry write, no ssh keys.
Prioritization reaches the broker only as a validated field inside the
message contract (D8) — never as broker access. Nothing outside the
four-item allow-list may appear in the CoS profile env; assertion 6
asserts this set both ways (positively: the four are present; negatively:
nothing else, starting with the denial list above).

**Enforcement honesty (per the 2026-11-10 review):** the CoS shares VM-Xa
with the gateway and manager, so this contract is enforced against the
CoS's *env* and its *capabilities*, not by network isolation. The capability
half is enforced by the post-M1 A+ hardening change (firewall/namespace so
the CoS profile's only permitted egress is the gateway endpoint and the
model-key proxy); until then, "no direct manager access" is by convention
and by the env contract, and TP-V2-M1 asserts both the env set negatively
(assertion 6) and the capability positively (assertion 11: an attempted
broker/manager-port connection from inside the CoS context must FAIL).

## 6. Conversation and management protocol (ask-before-submit)

1. Owner (desktop, thinking layer) researches/consolidates freely, then
   hands off: sends the request — natural language, optional attached
   artifacts (e.g., a BSD from the repo or uploaded files) — into the VM-Xa
   CoS conversation.
2. CoS **triages**: selects best-fit agent(s) from the roster (D7a), breaks
   the request into work packages, classifies each package's `priority`
   (D8) and dependencies (independent → submit in parallel, D9; dependent →
   hold in its backlog). The complete decomposition is published to the
   **master plan** on the external tracker (D12-rev), where the owner can
   review it; the CoS then **pulls the working subset** — the unblocked,
   priority-ordered items within the 5-agent window — onto its local
   board and drives those through the approval flow.
3. CoS **proposes** the decomposition (agent_ref + behavioral_spec +
   priority + ttl per package, per `schemas/message-v1.json`). Nothing is
   submitted.
4. Owner approves / rejects / requests changes (changes produce a new
   proposal version; the old id is void). The CoS **asks the owner exact,
   clear questions** instead of guessing whenever triage is ambiguous (D7d).
5. On approve, CoS submits through the gateway (parallel where independent).
   The manager validates every package — including the new `priority` field
   — and publishes message-v1. Broker/Temporal enforce priority and
   concurrency.
6. **Results loop**: CoS reads each task's report (gateway reports endpoint)
   and, where useful, the committed artifact in the project repo; it
   aggregates reports into a single human answer (its documented bus-org
   rollup job) and reports to the owner. **The CoS is the memory
   write-back actor:** after a report lands, the CoS writes the memory
   pointer entry (Hindsight write token, §5) — so "every task's learning
   is available to future tasks at boot" has an enumerated writer
   (third-pass drift pass). **Board reconciliation:** the working-set
   card moves to in-flight when the gateway acknowledges the submission
   (the gateway's status/report surface is the trigger — verified at
   build; if the unchanged gateway exposes no status signal, the card
   sits at "submitted" until the report arrives and this is stated in
   the build evidence); on boot and on demand, the CoS runs a
   **reconcile sweep** — every submitted task_id is checked against
   gateway truth, and drift is corrected board-side (the queue is
   execution truth, D12-rev). **Terminal states:** manager-rejected,
   voided, and TTL-failed items are archived-with-status on both tiers
   (working set and master plan) so every failure behavior in this
   section has a place to land. **Audit-trail provenance (third-pass
   drift pass):** the tracker's master-plan history is the *intent*
   trail; the local board history is *working intent*; the
   gateway/manager logs are the *enforcement* trail (what was actually
   submitted and validated). Whether the unchanged gateway already
   emits sufficient submit-side logs is a **build-time verification
   item** — cited if yes, enumerated as a change if no.
7. **Change management** (D10): new info mid-run is classified additive vs.
   corrective; corrective work becomes a follow-on revision package after
   the in-flight task completes, referencing its artifact.
8. Conversation state (backlog, open proposals, submitted tasks,
   dependencies) persists across reboots so nothing approved is orphaned.
   **Mechanism (D12-rev, owner 2026-11-10) — the two-tier work board:**
   **Tier 1, the master plan** — the CoS decomposes the behavioral
   specification into the complete plan on an **external tracker**
   (GitHub Issues by default; the exporter is tracker-agnostic, so ADO/
   Jira are swap-in), published by the **exporter** (which holds the
   tracker credential, staged gitignored per platform §9.1 — the CoS
   never holds a tracker key). The master plan is the **plan of record**:
   durable off VM-Xa by definition, human-reviewable (the owner reviews
   the proposed decomposition in the tracker before approving), and the
   intent audit trail. **Tier 2, the working set** — the CoS's local
   Hermes board holds the pulled subset (unblocked, priority-ordered,
   within the 5-agent window and dependency rules) and drives it through
   approval → submit → report. **Durability contract:** the master plan
   survives a total VM-Xa loss (it never lived there); the working set
   is rebuilt by re-pulling from the master plan after a profile
   restore, with every card's approval state re-verified — and any card
   whose approval state is ambiguous after restore goes **fail-safe to
   no-submit and surfaces to the owner** (never reconstructed
   optimistically; a card is submitted only from provably-approved
   state). **Write-ahead ordering:** approval is recorded on the card
   *before* the submit attempt; "submitted" is recorded only after the
   gateway acknowledges — making the crash-window deterministic.
   **Direction of truth:** tracker = plan; gateway/manager/queue =
   execution; local board = working cache. Status flows up (local
   transitions → tracker updates via the exporter); plan content flows
   down only via an explicit subset-pull; the exporter is offline-
   tolerant (tracker unreachable ⇒ the CoS works locally and syncs
   later). **The desk-never-door rule is unchanged:** neither tier can
   start work — only the approval flow → gateway → manager can. The
   project repo remains the source of truth for *project content* (D4);
   the tracker is the source of truth for the *plan*; the queue is the
   source of truth for *execution*. **Build-time verification items:**
   the local board's storage medium (durable host path/volume, not
   ephemeral), desktop-side board visibility, cross-project board
   isolation (a project's board must not leak across N registered
   desktop connections), board history retention/timestamps, the
   tracker choice, and the exporter's credential staging. TP assertion
   7 exercises: reboot recovery from the two-tier state, the
   crash-between-approval-and-submit window, and a **forced-corruption
   case** (a damaged/unreadable local board must yield no-submit and an
   owner surface, never resumption).

### Failure behavior (completed per the 2026-11-10 review)

- Model call fails mid-proposal → error to owner, no partial proposal.
- Model call fails at refinement → last good proposal stays valid; retry.
- Gateway submit fails → retry once, then report the failure with the
  gateway's error; the proposal stays `approved-unsubmitted` for manual
  resubmit.
- **Ambiguous submit outcome** (gateway timeout after the request may
  have landed) → the CoS retries with the **same `task_id`** (the
  contract's idempotency key — a duplicate is absorbed, never a second
  workflow), then reconciles via the gateway reports endpoint. task_id is
  never regenerated across retries; the per-package submit ledger keyed
  by task_id records each attempt.
- **Manager validation rejects an approved package** (bad agent_ref,
  out-of-bounds priority, repo_target not in the manifest) → the CoS
  re-proposes the repair, notifies the owner with the rejection reason,
  and re-enters the approval flow. An approved-but-invalid package is
  never resubmitted unchanged.
- **Task never reports** (TTL expiry, executor death) → the CoS polls the
  gateway reports endpoint past `ttl_s`, then surfaces the task as failed
  to the owner with the last known state; the backlog entry is closed as
  failed, not silently held.
- **CoS crash between owner approval and submission** → on restart, the
  CoS recovers from its two-tier state (D12-rev): working-set cards in
  `owner-approved` state (approval recorded before the crash, per the
  write-ahead ordering) are completed through the submission flow —
  ask-before-submit is preserved, nothing unapproved is submitted; a
  card whose approval state is ambiguous after recovery goes fail-safe
  to no-submit and surfaces to the owner. TP assertion 7 exercises this
  window explicitly.
- **Partial parallel submit** (some of N independent packages accepted,
  some failed) → the retry-once policy applies per failed package, not to
  the batch; accepted packages are never re-sent.

## 7. Gate / TP plan — TP-V2-M1

Structural assertions (all must PASS, strict gate rule):

1. Every `agent_ref` the CoS can propose exists in the roster `index.json`.
2. Manager validation passes end-to-end, **including the `priority` field
   pass-through and the approval-hash verification** (the M1 manager
   changes per the §4 enumeration, gated here). *(Formerly
   OQ4-conditional; unconditional since OQ4 was closed — the priority
   field lands with M1.)*
3. Priority + parallelism: two independent packages run concurrently; a
   higher-priority package is picked up ahead of a lower one — using the
   coarse `high`/`normal`/`low` encoding (OQ1). *(Formerly
   OQ4-conditional; unconditional since OQ4 was closed — the queue is
   declared with `x-max-priority` under the `ea-*` name during the
   rename's queue re-creation, so the redeclare happens exactly once.)*
4. TTL policy honored (`ttl_s` schema bounds respected end to end).
5. Model-call failure behavior matches §6 (forced-failure test).
6. Credential scope: the CoS profile env contains exactly the §5 set —
   asserted negatively (no GitHub token / queue creds present).
7. Reboot survival: kill the VM, bring the stack back up, gateway healthy,
   backlog/proposals survive; no orphaned approved-but-unsubmitted work.
8. Change management: corrective info mid-run produces a follow-on revision
   package after completion, referencing the prior artifact — no
   interruption of the running executor.
9. **No submission without owner approval** (the defining safety property
   of M1, added per the 2026-11-10 review): negative test — a proposal
   that was never approved produces zero gateway submit calls; a voided
   proposal id (superseded by a revision) cannot be submitted; every
   submission in the window maps to an approved card on the CoS board
   (D12). **Board-is-not-the-door:** no code path may move a card to
   "submitted" (or trigger a submission) except the approval flow — the
   gate asserts the board reflects, and never drives, queue state. The
   board clause is executed through a defined **board-inspection path**
   (third-pass drift pass): a direct read of the board's store (via the
   §9.5 build inventory) or a CoS status verb — named at build, not
   assumed.
10. **Approval-payload integrity — tamper-evidence, not tamper-prevention**
    (owner-approved resolution of the third-pass finding): the submitted
    work package carries an `approval_hash` — SHA-256 over the UTF-8
    behavioral_spec, whitespace-exact (canonicalization fixed) — as an
    additive optional message-v1 field landing in the **same gated
    change** as the manager's check (platform §5 field+consumer rule).
    At M1 the manager enforces exactly two checks: **retry integrity**
    (the same `task_id` must carry an identical spec hash across the
    §6 ambiguous-submit retries — the payload cannot be silently swapped
    between attempts) and **mismatch-reject-and-surface** (a
    non-matching payload is rejected and reported to the owner, never
    silently accepted). *The honest limit:* because the CoS supplies
    both the spec and its hash, the hash cannot prove the spec matches
    what the owner approved — it is tamper-*evidence* for post-hoc
    audit, not tamper-*prevention*. The control that stops an unapproved
    submission at M1 is the ask-before-submit approval loop itself
    (the recorded accepted residual of rung A/M1). The enforcement
    upgrade — the gateway records the hash at the moment the owner
    approves, making the pin owner-sourced — is the gateway-side
    approval-registration change: a later, separately-gated milestone
    (the gateway is unchanged in M1). The TP mismatch test injects the
    mismatch on the **manager side** (replayed payload vs recorded
    retry hash), not the board side.
11. **Credential-contract capability check** (see §5): from inside the
    CoS context, a connection attempt to the broker and to the manager
    port must FAIL — **conditional and deferred to the A+ gate** (third
    pass, per the second-pass review): at M1/rung A the CoS shares VM-Xa
    and the network with the gateway, so nothing enforces the failure
    yet; §5's honesty note states this. The A+ milestone gate asserts
    the capability check once the egress restriction exists. (Env-based
    access is still asserted negatively by assertion 6 at M1.)
12. **Desktop reconnection:** after the reboot of assertion 7, the
    desktop's registered remote gateway connection re-authenticates and
    resumes — **the pass artifact for the scoped-out alternative is the
    written scoping decision itself** (the one conditional-by-design
    assertion; third-pass drift pass).

**Judgment corpus (non-signed pre-gate eval; made runnable per the
third-pass condition 4, owner-approved):** located at
`version 2/judgment-corpus/` in the V2 repo — a versioned test asset of
the V2 system (the roster it tests against is upstream data, not the
test's home). **Two honest layers:**

- **Layer 1 — machine-checkable (scored exact-match, 100% required):**
  each fixture is a fixed input request plus the expected values of the
  fields the pipeline actually consumes — `agent_ref` (exact match),
  executor class (including the §8 edge cases: security-architect →
  hermes, data-engineer ETL → claude-code), priority class
  (high/normal/low), dependency edges (which packages wait on which),
  and the additive-vs-corrective label (D10). One special case class:
  the **ambiguity fixtures**, where the expected behavior is itself
  checkable — the CoS must escalate to the owner (ask, per D7d) and
  submit nothing.
- **Layer 2 — the judgmental remainder (unscored, owner-reviewed):** the
  quality of the behavioral_spec text and the elegance of the
  decomposition are recorded as an owner review in the gate evidence —
  never auto-scored. A green corpus run means "the CoS routes
  correctly," not "the CoS writes great specs"; the design says so
  explicitly.

**Initial size: 10–15 fixtures** — one straightforward routing case per
major agent category, the §8 harness edge cases, one dependency-chain
case, one parallel-independence case, one additive case, one corrective
case, and at least one ambiguity case. **Pass rule:** Layer 1 at 100%
blocks-or-clears TP signature (any miss = defect); Layer 2 is recorded,
not scored. **Trigger:** a CoS persona commit or roster-context change
requires a corpus re-run — a documented manual rule at M1 (the estate
has no CI yet); when the contract test suite gains CI (queue item 8's
direction), the corpus joins it. The corpus remains a **non-signed
pre-gate eval**: it gates TP signature procedurally; the signed
structural assertions stay the plumbing.

Plus one end-to-end: market-analysis example → proposal (with priority +
parallel packages) → owner approve → gateway → manager validation →
ephemeral executors → reports aggregated by the CoS → single human answer;
then a corrective-info injection mid-run → follow-on revision package.

## 8. Executor harness policy

The ephemeral executor harness set is **two images**, carried over from the
baseline build and confirmed by the owner on 2026-11-09:

| Harness | Image | Role |
|---|---|---|
| claude-code | `poc/claude-coder` | IT work whose artifact is code: coding, architecture-adjacent implementation, data pipelines, devops, security implementation. Purpose-built agentic loop (edit → run → test → iterate), like an IDE vs. a text editor. |
| hermes-agent | `poc/hermes-ephemeral` | Everything else: analysis, architecture judgment, business/requirements, compliance, coordination, QA, research — work whose artifact is a document or decision. |

Rationale and rules:

- **Harness ≠ model.** The harness (tooling environment) and the model (which
  LLM) are independent per-agent settings. The roster's Image line and Model
  line are separate fields; harness choice never dictates model choice.
- **The mapping is a roster default, CoS-applied.** The CoS reads the roster
  Image/Model lines as selection input; it judges edge cases (e.g.,
  security-architect = IT but non-coding → hermes; data-engineer ETL =
  coding → claude-code) using the roster's own per-agent encodings.
- **Proven on the estate:** both images hydrate the same persona/skills/tools files
  end-to-end; the coder path is gate-proven (TC-M3-04: clone → GLM edit →
  commit → push) and the hermes path (boot, hydration, report) likewise.
- **Admission criteria for any future third harness** (evaluated 2026-11-09:
  OpenCode and Codex CLI are the credible contenders on a fixed model;
  deferred): (a) a capability gap or model-family diversity the existing two
  cannot cover; (b) CVE-clean image per the §6-style gate; (c) passes the
  same hydration + report contract. Admission should be decided by a
  bake-off (same behavioral spec, same model, both harnesses), not opinion.
- Model specification and other per-agent configurable items (model pinning,
  TTL defaults, executor field in index.json) are a separate design topic,
  deliberately deferred.

## 9. VM-Xb carryover (test-run impact)

VM-Xb carries over from the baseline build **essentially unchanged**; the first V2 test run
replaces/upgrades only VM-Xa (adds the CoS Hermes profile beside the
unchanged gateway + manager) and points the desktop at it. Conditional
VM-Xb items only:

1. **Queue priority (D8):** if the message-v1 `priority` field is
   implemented, the agent.tasks queue must be redeclared with the
   `x-max-priority` argument (one-line change), paired with the manager
   pass-through. Sequencing — with M1 or after the first end-to-end proof —
   is OQ4.
2. **Worker capacity (OQ3):** optional env tuning for parallel packages.

Also a GitHub-side (not VM) item: V2 gets its own demo target repo
(e.g. `ephemeral-v2-demo`) rather than reusing `ephemeral-poc-demo`.

## 10. Repo layout & project manifest (config-as-declaration)

**Decision (owner, 2026-11-09):** single-repo-per-project is the **default
convention**; multi-repo is supported by declaration, not assumption. The
mechanism is a **project manifest** — a small config file living in the
project repo itself (the source of truth, D4):

```yaml
# project.yaml (illustrative shape, at repo root)
project: my-project
isolation_tier: xlg        # xlg = dedicated VM (ADR-0002); xsm = shared small-project VM
repos:
  - name: core
    url: github.com/arvisdev/my-project
    role: primary
  - name: docs
    url: github.com/arvisdev/my-project-docs
    role: docs
```

Rules:

- **Single repo** = manifest with one entry (or manifest absent → the
  primary-repo convention applies). Safe default.
- **Multi-repo** = explicit declaration. No pipeline change: message-v1
  already carries `repo_target` per task, so the CoS picks the repo from
  the manifest when decomposing.
- **CoS reads it; manager validates it:** a submitted package's
  `repo_target` must exist in the manifest — a nonexistent repo is
  rejected deterministically (same pattern as the priority field).
- The manifest is the natural home for the concurrency scope rules (§11)
  and, later, other per-project configurables (model pinning, TTL
  defaults, executor field) — one config surface the CoS reads and the
  manager validates.
- Changing the layout is a commit: versioned, reviewable, in history.

## 11. Multi-flow concurrency (resolves open item 1)

The concurrency design is one-coder-per-task (dedicated `task/<task_id>` branch) with
sequential same-repo execution, proven by TC-M3-07. Resolution of the
"N-parallel + worktrees" open item:

- **Worktrees rejected** — they solve a one-agent-many-checkouts problem
  that does not exist here: every ephemeral coder is its own container with
  a fresh clone, so N parallel containers already provide worktree-grade
  isolation (separate filesystems, separate credentials, zero survivors).
- **Risk taxonomy for parallel coders on one repo:** (1) disjoint file
  scope → safe to parallelize; (2) overlapping scope → pushes don't
  conflict, merges do — parallelize only if rework is acceptable; (3)
  semantic dependency → must be sequenced (CoS dependency graph, D9).
- **Judgment vs enforcement:** the CoS decides which packages are
  scope-disjoint and may run in parallel; deterministic enforcement arrives
  as an optional **file-scope declaration** in the work package — the
  manager refuses (or queues) a second task whose scope intersects an
  in-flight task on the same repo. Omitted scope defaults to **exclusive**
  (serialize same-repo tasks): safe by default, parallelism by declaration.
- **Merges:** branch-per-task already yields PR-able branches; merging is
  the github-operations-specialist's or the owner's job, with QA
  verification. No new machinery.
- **Sequencing:** M1 keeps same-repo coder tasks sequential (CoS backlog
  orders them; parallelism across different agent types/repos is already
  live and is the common case — zero VM-Xb touch, consistent with §9).
  The scope-declaration + manager exclusion rule is a later, separately
  gated milestone (one schema field, one manager check).

## 12. Open questions (from the 2026-11-09 discussion)

- **OQ1 — priority encoding: CLOSED (owner, 2026-11-10).** Coarse
  three-level enum — `high` / `normal` / `low`; the manager rejects
  anything else. See D8 for the rationale. The declared value is logged
  at the manager so declare-everything-high skew is visible and
  auditable.
- **OQ2 — desktop project naming UX:** the desktop registry names gateways;
  confirm the owner's preferred per-project naming convention.
- **OQ3 — worker capacity:** concurrency tuning on VM-Xb (worker count) as
  parallel packages become the norm (carried V2 open item; the platform
  §9.3 capacity model gives it numbers, not guesses).
- **OQ4 — priority-field sequencing: CLOSED (owner, 2026-11-10).** The
  `priority` field is implemented **with M1** — the field and its
  consumer (the manager pass-through) land in the same gated change per
  platform §5's rule, and the `x-max-priority` queue argument is
  declared once, under the final `ea-*` name, during the rename's queue
  re-creation. The former "first test run touches only VM-Xa" benefit
  was already superseded by the build-start security items (registry
  TLS, tokens), so deferral had no remaining advantage.
- **Manifest milestone:** the `repo_target`-vs-manifest check is gated
  with whichever milestone carries it (§4) — that milestone is recorded
  here so the deferral is not orphaned (third-pass drift pass): it is
  the **repo-manifest/manifest-check milestone**, queued after M1
  alongside the scope-declaration milestone.
- **Model specification & configurables:** per-agent model pinning, TTL
  defaults, and the executor field in index.json — separate upcoming design
  topic (likely hosted in the §10 project manifest or a sibling file).
- **Secure key management:** deferred at the owner's request (2026-11-09);
  baseline = the D-secret-vault direction (vault on VM-Xa as the
  credential-issuing authority).

## 13. Rejected alternatives

- **Bespoke CoS HTTP API on vm-xa (draft v1, Q1 answer of 2026-11-09
  morning)** — superseded by the native desktop gateway registry: Hermes
  Desktop already supports multiple named, always-connected remote gateway
  connections with session-token auth; a custom API would duplicate that
  mechanism and add a component to build and gate.
- **MCP server on the front-of-house VM** — adds a new protocol/process class
  for no capability the native gateway link lacks.
- **SSH/CLI access from the desktop** — grants shell reach into VM-Xa,
  violating the desktop-stays-credential-free boundary.
- **Desktop-held project registry / desktop-side routing layer** — the
  desktop holds no project state (D4/D5); projects are addressed by which
  gateway conversation the user is in.
- **One shared CoS serving multiple projects** — rejected: per-project
  isolation (memory, sessions, repo context) requires a resident CoS per
  VM-Xa (D6).
- **Autonomous submit mode** — deferred to a later, separately-gated
  milestone (Q2).
- **CoS as an ephemeral worker (`eph-chief-of-staff`)** — the roster entry
  stays for principals needing coordination artifacts; intake coordination
  needs a persistent resident (decided 2026-11-08).
- **CoS with direct queue access for prioritization** — rejected: priority
  is declared in the package and applied by the manager (D8); direct broker
  access would break "the agent proposes, the code disposes."
- **Mid-flight interruption / cancellation of running ephemeral agents** —
  rejected for M1: wait-then-follow-on (D10) works within the proven
  one-shot contract; true cancellation is a later, separately-gated
  milestone.
- **A third executor harness in M1 (OpenCode, Codex CLI, Gemini CLI, Aider,
  Goose/Crush evaluated 2026-11-09 on a fixed model, GLM 5.3 Flash)** —
  deferred: claude-code and hermes cover the capability space (IDE-class
  coding vs. everything else); adding a harness costs an image, CVE surface,
  and gate work. OpenCode is the leading future contender; admission is by
  the §8 bake-off criteria, not opinion.
- **New VM or new credentials class** — rejected (decided 2026-11-08).
