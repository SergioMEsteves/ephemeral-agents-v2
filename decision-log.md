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
