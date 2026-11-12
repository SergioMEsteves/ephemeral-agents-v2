# V2 decision log — append-only

Every decision that shapes Version 2 is recorded here with its date,
rationale, and rejected alternatives. The V1 decisions are inherited from
the V1 record (`arvisdev/ephemeral-agents`, decision logs in
`deploy/m0/decision-log.md` and `deploy/m5/decision-log.md`, plus the book's
Chapter 12); this log starts at the V2 kickoff.

## 2026-11-08 · V2 kickoff — two-repo split

- **Decision:** Version 2 is developed in this **private** repository;
  the V1 record (`arvisdev/ephemeral-agents`) stays **public and frozen**.
- **Rationale:** GitHub visibility is per-repo, not per-folder. The V1
  record (thesis, design, proof, book) is a public artifact; V2 work needs
  private freedom. Two repos give both without per-folder ACLs (which
  GitHub does not offer) or mirror-push discipline (which risks leaks).
- **Rejected alternatives:** making the whole repo private at V2 (hides the
  public V1 record); keeping V2 in the public repo uncommitted (no version
  control for the most important work); fork-with-deletions (V1 content
  would remain in this repo's history; a fresh init with a hash citation is
  cleaner).
- **V1 baseline cited:** `arvisdev/ephemeral-agents @
  14bf62dc81729ed0ece355c30b5b6888d4fbf058`.

## 2026-11-08 — Baseline sync from the V1 record

- Synced the V1 record at `3c2b723` into this repo: the book (15 chapters,
  including the Evaluator's Guide and the reboot/restart lessons), the full
  executable layer (`deploy/`: idempotent install scripts, parameterized
  compose files, `deploy/restart-stack.sh`, operational notes in
  `deploy/README.md`), the license set, and the de-identified record
  documents (findings report, retrospective).
- All synced content carries V1's de-identification sweep: no IP addresses,
  usernames, passwords, or API keys in any tracked file; configuration values
  are env-driven (gitignored env files supply them at deploy time).
- Standing rule adopted: V2 begins from a synced baseline and stays synced —
  V1 fixes are backported here (and vice versa per the established
  convention); the reference hash above is re-cited, never "latest."
- First milestone unchanged: the Chief-of-Staff Hermes agent (see README).

## 2026-11-08 — V1 history rewrite; reference hash rotated

- The V1 public repo purged `POC-IP-Addresses.txt` (the estate IP inventory)
  from its entire git history (git-filter-repo, force-pushed): the owner
  ruled no IP addresses may be retrievable from any downloadable artifact,
  and history counts. All V1 commit hashes changed as a result.
- Reference hash rotated: the V1 baseline this repo cites is now
  `4de7a06` (the rewritten equivalent of the previously cited `3c2b723`).
  The synced `book/` and `deploy/` trees are content-identical to the
  previously synced state — only V1's `version 1/` documents (not carried
  here) changed in the same sweep (private llm-wiki URL references
  replaced with non-linking placeholders because the private repo 404s for
  public visitors).
- Note: previously cited hashes (`14bf62d`, `3c2b723`) no longer resolve on
  the V1 remote; this log retains them deliberately as historical markers.

## 2026-11-09 — V2-M1 open questions settled; design doc drafted

- **Q1 (desktop↔CoS connection):** authenticated HTTP API on the
  front-of-house VM (vm-xa, :8090), consumed by the desktop Hermes as a
  tool; desktop stays credential-free. Owner took the recommendation.
- **Q2 (approval mode):** ask-before-submit — CoS proposes the
  decomposition, owner approves, then it submits. Autonomous mode deferred
  to a later, separately-gated change.
- Design doc drafted: `version 2/V2-M1-cos-design.md` (API surface, runtime
  shape, strict credential contract — one model key + gateway client only,
  no GitHub token / queue access; conversation protocol with failure
  behavior; TP-V2-M1 gate plan; rejected alternatives).
- Next: owner reviews the draft, then build (CoS container + compose on
  vm-xa) and the TP-V2-M1 gate.

## 2026-11-09 (later) — V2-M1 design rethought: native gateway link; CoS management model

The owner reopened the desktop↔VM-Xa design before review. Verified against
the official Hermes docs (`user-guide/multi-connection-desktop`) that Hermes
Desktop natively registers multiple named, always-connected remote gateway
connections (session-token auth) — so draft v1's bespoke CoS HTTP API is
unnecessary. Decisions recorded in the rewritten
`version 2/V2-M1-cos-design.md` (DRAFT v2):

- **Q1 reversed:** connection = native Hermes Desktop gateway registry; no
  bespoke CoS HTTP API. Draft v1's API design moves to rejected
  alternatives.
- **D3** CoS = Hermes profile on the VM-Xa gateway (long-lived Hermes Agent
  instance with the CoS persona), not a hand-rolled service.
- **D4/D5** the project's source of truth is the git repo the VM-Xa agent
  works from; the desktop holds no project state (it may upload files into
  the session). "VM-Xa" now means any VM with a Hermes Agent deployed.
- **D6** one project = one VM-Xa = one gateway = one resident CoS; desktop
  registers N gateways; projects isolated by default.
- **D7** CoS management model: best-fit agent selection from the roster;
  own working backlog for ordering; change-request triage; escalate to the
  owner with exact questions when judgment is insufficient.
- **D8/D9** prioritization: CoS *declares* an optional `priority` field in
  message-v1; manager validates and applies; RabbitMQ/Temporal enforce.
  Parallelism: independent packages submitted concurrently (pipeline
  already concurrent).
- **D10** change management: no mid-flight interruption of ephemeral
  agents; additive info held, corrective info becomes a follow-on revision
  package after completion; true cancellation deferred to a later gated
  milestone.
- New open questions OQ1 (priority encoding), OQ2 (project naming UX),
  OQ3 (VM-Xb worker capacity).
- Note: the `priority` field is a deliberate, gated change to the
  "manager unchanged" boundary (schema + pass-through); TP-V2-M1 gate
  updated accordingly.

## 2026-11-09 (second update) — harness policy; VM-Xb carryover

- **Executor harness set stays at two** (owner): `poc/claude-coder` for
  IT/code-artifact work, `poc/hermes-ephemeral` for everything else — the
  roster's existing Image mapping, now recorded as design policy with its
  rationale (IDE-vs-editor analogy), the harness≠model rule, and admission
  criteria for any future third harness (bake-off on a fixed model; the
  2026-11-09 evaluation named OpenCode the leading contender, Codex CLI
  second; deferred, not built).
- **VM-Xb carries over essentially unchanged** for the V2 test run: only
  VM-Xa changes (CoS profile added beside the unchanged gateway/manager).
  Conditional VM-Xb items only: queue `x-max-priority` redeclare if/when
  the priority field lands (OQ4: with M1 vs. post-first-proof), and
  optional worker-capacity tuning (OQ3). V2 gets its own demo repo
  (e.g. `ephemeral-v2-demo`), a GitHub-side item.
- Design doc updated: new §8 (Executor harness policy), §9 (VM-Xb
  carryover), OQ4 added; model specification & configurables recorded as a
  deferred topic.

## 2026-11-09 (third update) — repo manifest; concurrency resolution

- **Single-repo-per-project is the default convention; multi-repo is
  declared, not assumed** (owner): a per-project manifest (config file in
  the project repo) declares the repo layout; the CoS reads it, the manager
  validates `repo_target` against it. New design §10.
- **V1 open item 1 (multi-flow concurrency) resolved** (design §11):
  worktrees rejected as unnecessary in the ephemeral model; M1 keeps
  same-repo coder tasks sequential via the CoS backlog (cross-agent-type /
  cross-repo parallelism already live); safe parallelism arrives later via
  an optional file-scope declaration with deterministic manager exclusion
  (omitted scope = exclusive — safe by default).
- Open questions OQ5 list extended: model specification & configurables
  (deferred topic, likely manifest-hosted) and secure key management
  (deferred at the owner's request; D-secret-vault baseline).

## 2026-11-09 (fourth update) — open-items queue adopted; config structure reset

- **9-item open-items queue adopted** (owner): the remaining V1→V2 topics are
  worked one-by-one, with owner clarifying questions per item. Order:
  (1) model specification & configurables, (2) secure key management,
  (3) ephemeral isolation level, (4) embeddings provider, (5) llm-wiki
  curation automation, (6) upstream dependency refresh policy, (7) umbrella
  compose / reboot-surviving stack, (8) contract test suite,
  (9) production-hardening list (ch15 POC boundary).
- **Item 1 opened and reset:** the model-specification/config-file structure
  discussion (config file format, project.yaml field structure, precedence
  chains, roster→catalog derivation) was opened 2026-11-09 and **stopped by
  the owner before any decision landed — it restarts from scratch later**.
  Nothing from that discussion is a decision. §10 (manifest concept) and
  §11 (concurrency rules) remain decided as previously committed.

## 2026-11-10 — platform decisions: naming, memory, concurrency, embeddings, queue policy, isolation ladder, V1 lessons

- **V2 naming family adopted (owner):** V2 is production-bound, not a POC.
  All V2-owned components use the `ea-` family: network `ea-net`,
  images `ea/hermes-ephemeral` / `ea/claude-coder`, env prefix `EA_*`,
  `ea-*` container/queue names. Decided now, executed as the opening
  action of the V2 build phase; the baseline-synced `deploy/` tree keeps
  V1 names until then (it is verbatim V1 evidence). From the rename
  onward, V2 design docs reference only V2 names; V1 carryover is stated
  once as provenance.
- **Memory pointer-store convention adopted (owner):** documents live
  only in the project repo; Hindsight stores pointers only; CoS on VM-Xa
  writes, memory VM stores, repo is content. Pointers also live in the
  repo's own history index. New doc `version 2/V2-platform-design.md` §2.
- **Concurrency default decided (owner):** default 5 ephemeral agents in
  flight, configurable per project via the manifest
  (`max_parallel_agents`); M1 keeps same-repo coder tasks sequential
  (design §11); full effect when the scope-declaration milestone lands.
- **Embeddings provider resolved as policy (owner):** evidence-driven —
  build M1 on the zero-vector fallback; trigger a small self-hosted
  embeddings model on the memory VM only if pointer recall proves poor.
- **Queue-shape policy adopted (owner):** message-v1 evolves additively
  only; breaking changes trigger a versioned message-v2 with transition;
  new message types as small gated additions; topic topology unchanged
  until a new type is needed.
- **Isolation level decided (owner):** ladder with tripwires — A
  (co-located containers) for M1; A+ (rootless runtime + per-task egress
  allow-list) adopted as a separately-gated hardening change immediately
  after M1's gate; B (gVisor-class) triggered by untrusted task content;
  C (per-task micro-VM) triggered by multi-tenant or outside-the-boundary
  execution. Full pros/cons and triggers in platform-design §6.
- **V1 lessons pre-applied (owner):** the V2 build reproduces the V1
  build process with each V1 lesson mapped to the concrete build step
  that embodies it (platform-design §7): repo-canonical runtime
  artifacts, contract tests before gates, artifact-naming gate
  assertions, integration-path gates, baked reboot survival, registry
  pinning, hard hygiene gates, upstream pin tracking, envelope
  self-sufficiency, inventory-first chassis.
- New document: `version 2/V2-platform-design.md` (DRAFT v1) records all
  of the above; WORKING-STATE updated to match.

## 2026-11-10 (second) — end-to-end design review; findings accepted and applied; build-phase plan

- **Full end-to-end design review performed** (enterprise architecture,
  software engineering, network engineering, security architecture, SRE —
  28 findings: 4 critical, 10 major, 9 minor, 5 observation) and the
  findings **accepted by the owner**. Verdict: approve with conditions —
  no owner-decided item reopened.
- **Critical findings applied:** (1) schema-evolution mechanics corrected
  — message-v1's `additionalProperties: false` contradicts the
  "consumers tolerate unknowns" wording; additive fields now land in the
  schema with defaults, in the same gated change as their consumers
  (platform §5). (2) Prompt-injection steering of the CoS: structured
  diff-style proposal surface, hash-pinned approval payload, untrusted-
  content rules in the persona, submit audit log (M1 design §7
  assertions 9–10). (3) The no-submit-without-approval invariant is now
  gate-asserted (M1 §7.9). (4) Registry transport integrity — TLS +
  internal CA + basic auth + digest-pinned pulls, as a small gated item
  at build start, not the deferred vault (platform §9.1).
- **Major findings applied:** CoS state persistence specified
  (`cos-state/state.json` in the project repo, written per transition —
  M1 §6.8); failure behaviors completed (ambiguous submit with stable
  task_id, manager rejection, never-reporting task, crash between
  approval and submit, partial parallel submit — M1 §6); credential
  contract enforcement honesty — capability assertion added (M1 §5,
  assertion 11); A+ re-specified as segmentation + rootless, gate asserts
  both (platform §9.2); llm-proxy/Hindsight auth + reach restriction
  (§9.1); dashboard publisher-identity control within the LAN-open
  decision (§9.1); GitHub token custody + accepted residual on rung A
  (§9.1); capacity model + 5-concurrent soak test + OOM kill-order
  (§9.3); CoS observability minimum (§9.3); D6 explicitly supersedes the
  2026-11-08 "no new VM" note for multi-project growth (§9.4); judgment
  corpus as non-signed pre-gate eval and persona-change regression
  harness (M1 §7).
- **Build-phase file-level impact inventory adopted (owner directive):**
  before the first V2 milestone runs, every file required for a full
  clean V2 build/deployment/installation/checks is enumerated and mapped
  (file → change → decision/finding served → gate that exercises it);
  the rename micro-gate and all later gates assert against it (platform
  §9.5).
- **V2 build process committed (owner directive):** V2 reproduces the V1
  process end-to-end — staged M0-style build with per-stage checks,
  per-milestone TPs and signed results under the gate rule, a **V2 issue
  ledger** (symptom → wrong assumption → root cause → the rule we now
  follow) so V2's own issues and corrective actions become part of the
  V2 documentation, a contract test suite as a named TP-V2-M1
  prerequisite, and a closing findings report (platform §9.6).
- **Rename execution order fixed:** rename completes before any OQ4
  queue redeclare; rename is its own micro-gate (grep-clean, baseline
  re-run green under ea names, digest-equality re-tag, committed V1→V2
  mapping table) (platform §9.7).
- **V2 book timing decided (owner):** the V2 edition of the book is
  written **after** the full V2 installation/deployment is proven
  working — the closing deliverable — so that everything the V2 build
  found (issue ledger, corrective actions, measured numbers, gate
  evidence) is written into it from the record rather than predicted
  before the fact. It is sequenced after the closing findings report in
  the platform-design §9.6 build process; it is not part of the build
  phase.

## 2026-11-10 (third) — second-pass end-to-end design review; report persisted

- **Second-pass review performed** against the amended design set (same
  five expert lenses; closure verification + fresh analysis). Verdict:
  **ready-with-conditions**; all first-review closures verified as
  correctly applied, none reopened owner decisions. Full report persisted
  as `version 2/V2-design-review-report.md`.
- **Convergent critical finding (both panels, introduced by the
  amendments):** `cos-state/state.json` (M1 §6.8) contradicts the §5
  credential contract — the CoS is denied a GitHub token yet must push
  state and read repo truth. **Owner decision required:** (a) scoped
  repo credential for the CoS (amend §5 + assertion 6), or (b) local
  volume + Hindsight pointer (amend §6.8). Blocks TP-V2-M1 signature.
- Other majors: state push-race convention undefined; approval-hash
  verifier unowned (gateway "unchanged" vs need for a hash check —
  manager is the natural verifier, must be enumerated); assertion 11
  untestable at M1 (mark conditional/deferred to A+); assertion 2 needs
  the OQ4-conditional marking; A+ segmentation severs the memory-
  hydration contract (choose: forwarder read-only allow-list or
  spawn-side hydration); shared Hindsight token gives executors write
  (choose: write/read token split); judgment corpus not yet runnable.
- Four conditions before the build gate: (1) resolve the CoS credential
  contradiction; (2) reconcile assertions 2/3/10/11; (3) record the A+
  memory-hydration + token-split decisions; (4) fix doc drift
  (WORKING-STATE next actions, subsumed queue items, stale cross-refs).
- Residuals recorded: the §9.1 controls create new secrets whose
  staging/rotation is unspecified (vault deferred — their staging must
  still be named in the gated items); prompt-injection soft residuals
  accepted for rung A/M1 (human approval loop remains the real control;
  watch-item for isolation rung B).

## 2026-11-10 (fourth) — D12 adopted: kanban board as the CoS work board

- **D12 (owner):** the CoS maintains its work state on its **native
  Hermes kanban board** — one per project CoS; card = work package
  (agent_ref, behavioral_spec, priority, ttl, dependencies); columns
  proposed → owner-approved → submitted → in-flight → reported → rolled
  up; corrective follow-ons as linked cards; report events move cards.
- **The board is the desk, never the door:** the queue (RabbitMQ/
  Temporal) remains the only execution truth; cards reach "submitted"
  only via the approval flow (gateway → manager validation); board state
  reflects, never drives, queue state — gate-asserted (TP 9 amended).
- **This RESOLVES the second-pass review's condition 1 (critical)** — the
  `cos-state/state.json` mechanism, which would have required the CoS to
  push to GitHub in violation of §5's no-GitHub-token contract, is
  **replaced** by the board as the CoS state store of record: it lives
  with the CoS profile on VM-Xa, is reboot-durable, and needs no new
  credential. The project repo remains the source of truth for project
  content (D4); the board for CoS work state.
- Board history doubles as the submit-side audit trail (the observability
  minimum). Desktop-side board visibility is a named build-time
  verification item. Docs amended: M1 design (D12 row, §6.8 mechanism,
  failure-behavior recovery, TP assertion 9), feature list (§1).

## 2026-11-10 (fifth) — third-pass end-to-end review; report updated

- **Third-pass review performed** (same two-panel method) against the
  fully amended state; the updated report is persisted in
   `version 2/V2-design-review-report.md` (third-pass section appended).
  - **Closures verified:** D12 confirmed by both panels as the correct
   resolution of the credential contradiction; assertion conditionals
   consistent; A+ hydration/token-split decisions recorded correctly. No
   owner-decided item reopened.
  - **Verdict: ready-with-conditions (narrowing).** New findings, both
   panels convergent on the substantive two: (1) the approval-hash
   mechanism has no honest transport — the manager can't read the board,
   a message-carried hash is tautological; fix = message-v1 hash field +
   M1 manager check downgraded to retry integrity + mismatch-reject,
   §7.10 reworded to tamper-evidence, canonicalization defined, gateway-
   side approval registration as the later enforcement change;
   (2) the board's durability/fail-safe story is asserted not specified —
   fix = storage as build-time verification item, backup/export,
   fail-safe-to-no-submit on ambiguous/unreadable state, write-ahead
   ordering, corruption case in TP 7. Plus: §5's "exactly three
   credentials" must be restated as the enumerated allow-list now that
   the CoS legitimately holds a Hindsight write token and the llm-proxy
   CoS-class token (a conforming build would fail assertion 6 as
   written); the judgment corpus remains not runnable (carried through
   both passes — fixtures, location, threshold required before the gate);
   and the minor/drift set (audit-trail provenance split — board =
   intent trail, gateway/manager log = enforcement trail; board/queue
   reconcile + terminal states; TP board-inspection path; advisory-only
   attribution header; A+ hydration re-verification list + write-back
   actor; new cross-VM llm-proxy dependency; doc drift).
  - **Five conditions remain** before the build gate opens (report §5):
   §5 allow-list restatement, hash-mechanism fix, board durability
   contract, runnable judgment corpus, drift pass. With those applied,
   the design is ready to build.

## 2026-11-10 (sixth) — de-POC sweep: V2 repo carries no redundant POC documents

- **Owner directive:** remove POC-related documents not needed for V2;
  modify those that are needed to reference V2 instead.
- **Removed from V2 (owner directive):** the two root POC documents —
  `Initial-POC-Findings-Report.md` (the signed V1 evidence record) and
  `POC-Retrospective-and-Insights.md` (the lessons digest). They are
  V1-record artifacts, verbatim in the frozen public V1 repo
  (github.com/arvisdev/ephemeral-agents, HEAD `2c97797…` — verified
  present before removal); duplicating them here served no V2 purpose
  and the V2 docs already cite V1 by hash. V2's own findings report and
  issue ledger are build-phase closing deliverables (platform §9.6).
  README and book/README pointers updated to cite the V1 location.
- **Deliberately retained:** `book/` (the V1 record's book — provenance
  for the design docs, "V2 extends or supersedes, never silently
  rewrites"); `deploy/` (the V1 evidence baseline — its V1 names are
  retained until the `ea-` rename micro-gate, platform §1); the `poc-*`
  name references inside `deploy/` (V1 evidence verbatim).
- **Modified:** `schemas/message-v1.json` metadata de-POC'd — title
  ("ephemeral-agents POC task message" → "ephemeral-agents task
  message") and description ("Owned by the M1 delivery plan WP-1.1" →
  the V2 schema-policy owner reference, platform §5). Metadata-only
  change: no field, required, or additionalProperties semantics touched
  — the §5 rule ("title corrected at the same first touch") is satisfied
  early by this owner-directed sweep, recorded here as that first
  touch.

## 2026-11-10 (seventh) — D12-rev: two-tier work board; conditions 2–3 applied; ADR-0001

- **D12-rev (owner): the two-tier work board.** Tier 1 — the **master
  plan** on an external tracker (GitHub Issues default; ADO/Jira
  swap-in): the CoS decomposes the behavioral specification into the
  complete plan, published by an **exporter** that holds the tracker
  credential (the CoS never does). The master plan is the plan of
  record: durable off VM-Xa, human-reviewable in the approval flow, and
  the intent audit trail. Tier 2 — the **working set** on the CoS's
  local Hermes board: the CoS pulls a logical subset (unblocked,
  priority-ordered, within the 5-agent window) and drives it through
  approval → submit → report. Direction of truth: tracker = plan;
  gateway/manager/queue = execution; local board = cache. Status flows
  up; plan content flows down only via explicit subset-pull;
  offline-tolerant. Desk-never-door unchanged. Full rationale,
  consequences, and rejected alternatives: `version 2/adr-0001-cos-work-board.md`.
- **Documentation directive (owner):** the work-board and approval areas
  are complex — the V2 book must give them special plain-language
  attention for the general reader, and architectural decision records
  (this ADR-0001 is the first) carry the senior-technical depth. ADRs
  join the V2 documentation set as a standing class.
- **Condition 2 applied (owner-approved recommendation):** the
  approval-hash mechanism is now honest — `approval_hash` as an additive
  message-v1 field (SHA-256, UTF-8, whitespace-exact canonicalization)
  landing in the same gated change as the manager check; M1 manager
  checks = retry integrity + mismatch-reject-and-surface; §7.10 reworded
  to tamper-evidence (the ask-before-submit loop remains the control);
  gateway-side approval registration recorded as the later enforcement
  upgrade; the TP mismatch test injects on the manager side.
- **Condition 3 applied (on the D12-rev basis):** the durability
  contract — master plan survives total VM-Xa loss by construction;
  working set rebuilt by re-pull with approval-state re-verification;
  fail-safe to no-submit on ambiguous/unreadable approval state;
  write-ahead ordering (approval precedes submit attempt; "submitted"
  follows gateway ack); forced-corruption case added to TP assertion 7;
  build-time verification items named (board storage medium, desktop
  visibility, cross-project isolation, board-history retention, tracker
  choice, exporter credential staging).
- **Condition 1** was applied in the previous commit (the §5 four-
  credential allow-list). Remaining conditions: 4 (runnable judgment
  corpus) and 5 (drift pass).

## 2026-11-10 (eighth) — conditions 4 and 5 applied; design ready to build

- **Condition 4 applied (owner-approved):** the judgment corpus is now
  runnable — `version 2/judgment-corpus/` in the V2 repo; two layers
  (Layer 1 machine-checkable fixtures — agent_ref, executor class incl.
  the §8 edge cases, priority class, dependency edges,
  additive/corrective label, plus ambiguity fixtures whose expected
  behavior is escalation-with-no-submission — scored exact-match, 100%
  required; Layer 2 judgmental remainder — behavioral_spec quality —
  unscored, owner-reviewed in the gate evidence); 10–15 initial
  fixtures; re-run on CoS persona or roster-context change (manual rule
  at M1; joins CI later); remains a non-signed pre-gate eval.
- **Condition 5 applied (drift pass, all items):** audit-trail provenance
  split (tracker = intent, board = working intent, gateway/manager logs
  = enforcement; gateway submit-logging = build-time verification item);
  board/queue reconciliation (in-flight trigger = gateway ack, verified
  at build; on-boot/on-demand reconcile sweep; terminal
  archived-with-status states for manager-rejected/voided/TTL-failed on
  both tiers); TP board-inspection path defined (store read or CoS
  status verb, named at build); attribution header declared advisory
  (caps key on token + container identity); A+ gate re-verification
  list named (M4_MEMORY_HYDRATE semantics, entrypoint path, lifecycle
  token custody) + degraded-mode rule (Hindsight down at spawn ⇒ fail
  or logged-degraded, never silent) + the **CoS as the memory write-back
  actor** added to §6's results loop; the CoS→VM-Xb llm-proxy cross-VM
  dependency added to the §9.5 endpoint table; M1 §1 "unchanged" wording
  corrected; assertion 12's pass artifact stated (the written scoping
  decision); feature-list least-privilege and approval-integrity lines
  corrected; manifest-check milestone named in the open questions;
  WORKING-STATE header and next-action item 4 status-corrected.
- **All five third-pass conditions are applied. Design verdict: ready to
  build.** Next: the build phase opens with the `ea-` rename micro-gate
  and the file-level impact inventory, then the staged build and M1 /
  TP-V2-M1. Open questions OQ1/OQ4 remain owner calls (recommended:
  coarse 3-level priority encoding; priority field lands with M1 per
  the field+consumer rule).

## 2026-11-10 (ninth) — OQ1 and OQ4 closed; no open questions block the build

- **OQ1 CLOSED (owner):** the message-v1 `priority` encoding is the
  coarse enum `high` / `normal` / `low`. Rationale: the declarer is an
  LLM — a 1–10 scale would carry precision the judgment source doesn't
  have; three levels survive judgment, make declare-everything-high
  skew visible and auditable (the manager logs the declared value), and
  map cleanly onto RabbitMQ `x-max-priority` / Temporal priorities.
  Finer ordering stays in the CoS's own backlog sequence and submission
  timing. Out-of-range values are rejected outright by the manager.
- **OQ4 CLOSED (owner):** the `priority` field is implemented **with
  M1** — field and consumer land in the same gated change (platform §5
  rule); the `x-max-priority` queue argument is declared once, under
  the final `ea-*` name, during the rename's queue re-creation (the
  rename-before-OQ4 rule, platform §9.7, is thereby satisfied
  naturally). Deferral's "first test run touches only VM-Xa" benefit
  was already superseded by the build-start security items.
- TP assertions 2 and 3 are now **unconditional** (the former
  OQ4-conditional markings removed); the M1 gate plan has no deferred
  clauses except assertion 11 (A+-deferred, by design) and assertion 12
  (conditional-by-design, pass artifact = the written scoping
  decision).
- **No open questions block the build.** Remaining open items are
  OQ2 (desktop naming UX — cosmetic, decided at setup), OQ3 (worker
  capacity — decided by the §9.3 capacity model at build), and the
  queued/deferred topics. **The build phase may open:** `ea-` rename
  micro-gate → file-level impact inventory + endpoint table →
  build-start security items → staged build → M1 / TP-V2-M1.
