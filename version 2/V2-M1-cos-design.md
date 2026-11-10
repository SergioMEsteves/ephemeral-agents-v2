# V2-M1 — Chief-of-Staff Agent Design

*Status: DRAFT v2, in active design discussion with the owner (2026-11-09).
Supersedes draft v1; the v1 bespoke-HTTP-API connection design is recorded in
§9 as a rejected alternative.*

## 1. Goal

A persistent resident **Hermes Agent** — the bus-org **chief-of-staff** persona
— runs on the front-of-house VM ("VM-Xa"; from 2026-11-09 the term means any
VM with a Hermes Agent deployed) between the **unchanged** gateway and the
**unchanged** manager. The owner talks to the CoS conversationally from the
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
| D8 | Prioritization | The CoS **declares** priority in the work package (new optional `priority` field in message-v1); the **manager validates and applies** it; RabbitMQ per-message priority and/or Temporal task-queue priority enforces pickup order. The CoS never touches the broker. |
| D9 | Parallelism | Independent packages are submitted concurrently and run in parallel (pipeline already supports this). Dependent packages are held by the CoS until the upstream report returns. |
| D10 | Change management | No mid-flight interruption of ephemeral agents. New information arriving while a task runs is classified: **additive** (held for future packages) or **corrective** (a follow-on revision package issued after the in-flight task completes, referencing its artifact). The CoS reads results via the gateway report and/or the project repo, then composes follow-on work. True cancellation of in-flight runs is a separately-designed later milestone (it moves an enforcement action into judgment's hands). |
| D11 | Conversation boundary | Gateway → manager → queue unchanged; the CoS is a client of the gateway, nothing more. |

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
- **Gateway and manager untouched** except for the single deliberate,
  gated change in §6 (priority pass-through).

## 5. Credential contract (strict)

The VM-Xa CoS profile receives exactly:

1. **One model key** — for its own LLM calls.
2. **Gateway session token** (inbound, for the desktop connection) — D3/§3.
3. **Gateway API credential** — to submit approved tasks; ordinary gateway
   client scope.

Explicitly **denied**: no GitHub token, no queue (RabbitMQ/Temporal) access,
no direct manager access, no registry write, no ssh keys. Prioritization
reaches the broker only as a validated field inside the message contract (D8)
— never as broker access.

## 6. Conversation and management protocol (ask-before-submit)

1. Owner (desktop, thinking layer) researches/consolidates freely, then
   hands off: sends the request — natural language, optional attached
   artifacts (e.g., a BSD from the repo or uploaded files) — into the VM-Xa
   CoS conversation.
2. CoS **triages**: selects best-fit agent(s) from the roster (D7a), breaks
   the request into work packages, classifies each package's `priority`
   (D8) and dependencies (independent → submit in parallel, D9; dependent →
   hold in its backlog).
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
   rollup job) and reports to the owner.
7. **Change management** (D10): new info mid-run is classified additive vs.
   corrective; corrective work becomes a follow-on revision package after
   the in-flight task completes, referencing its artifact.
8. Conversation state (backlog, open proposals, submitted tasks,
   dependencies) persists across reboots so nothing approved is orphaned.

### Failure behavior

- Model call fails mid-proposal → error to owner, no partial proposal.
- Model call fails at refinement → last good proposal stays valid; retry.
- Gateway submit fails → retry once, then report the failure with the
  gateway's error; the proposal stays `approved-unsubmitted` for manual
  resubmit.

## 7. Gate / TP plan — TP-V2-M1

Structural assertions (all must PASS, strict gate rule):

1. Every `agent_ref` the CoS can propose exists in the roster `index.json`.
2. Manager validation passes end-to-end, **including the `priority` field
   pass-through** (the one deliberate manager change, gated here).
3. Priority + parallelism: two independent packages run concurrently; a
   higher-priority package is picked up ahead of a lower one.
4. TTL policy honored (`ttl_s` schema bounds respected end to end).
5. Model-call failure behavior matches §6 (forced-failure test).
6. Credential scope: the CoS profile env contains exactly the §5 set —
   asserted negatively (no GitHub token / queue creds present).
7. Reboot survival: kill the VM, bring the stack back up, gateway healthy,
   backlog/proposals survive; no orphaned approved-but-unsubmitted work.
8. Change management: corrective info mid-run produces a follow-on revision
   package after completion, referencing the prior artifact — no
   interruption of the running executor.

Plus one end-to-end: market-analysis example → proposal (with priority +
parallel packages) → owner approve → gateway → manager validation →
ephemeral executors → reports aggregated by the CoS → single human answer;
then a corrective-info injection mid-run → follow-on revision package.

## 8. Executor harness policy

The ephemeral executor harness set is **two images**, carried over from V1
and confirmed by the owner on 2026-11-09:

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
- **Proven in V1:** both images hydrate the same persona/skills/tools files
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

VM-Xb carries over from V1 **essentially unchanged**; the first V2 test run
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

## 11. Multi-flow concurrency (resolves V1 open item 1)

V1 decided one-coder-per-task (dedicated `task/<task_id>` branch) with
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

- **OQ1 — priority encoding:** scale (1–10 vs. high/normal/low) for the
  message-v1 `priority` field.
- **OQ2 — desktop project naming UX:** the desktop registry names gateways;
  confirm the owner's preferred per-project naming convention.
- **OQ3 — worker capacity:** concurrency tuning on VM-Xb (worker count) as
  parallel packages become the norm (carried V2 open item).
- **OQ4 — priority-field sequencing:** implement the message-v1 `priority`
  field with M1 (queue redeclare + manager pass-through) or defer it until
  after the first end-to-end proof, making the first V2 test run touch
  nothing but VM-Xa.
- **Model specification & configurables:** per-agent model pinning, TTL
  defaults, and the executor field in index.json — separate upcoming design
  topic (likely hosted in the §10 project manifest or a sibling file).
- **Secure key management:** deferred at the owner's request (2026-11-09);
  baseline = V1's D-secret-vault direction (vault on VM-Xa as the
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
