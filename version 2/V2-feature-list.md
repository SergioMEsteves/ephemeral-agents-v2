# Version 2 — Feature List (the full offer)

*Status: DRAFT v1, 2026-11-10. Derived from the decided V2 design set:
`V2-M1-cos-design.md`, `V2-platform-design.md`, `V2-design-review-report.md`,
and the decision log. Status markers: **decided** (owner-approved, in scope),
**trigger-gated** (policy recorded, built only when its trigger fires),
**deferred** (owner-deferred topic, not in scope until reopened).*

## 1. Conversational intake — the Chief-of-Staff

- **Persistent resident CoS agent** on the front-of-house VM: the owner
  talks to it conversationally from Hermes Desktop — no structured POSTs,
  no capability keywords, no agent-picking by hand. *(decided, M1)*
- **Natural-language decomposition:** one request → proposed work packages
  (agent, behavioral spec, priority, TTL, dependencies) drawn from the full
  45-agent roster across three orgs (business, enterprise-architecture,
  ephemeral). *(decided, M1)*
- **Ask-before-submit safety:** nothing runs until the owner approves;
  exact clarifying questions instead of guessing; no submission without
  approval is a signed gate assertion. *(decided, M1)*
- **Prioritization:** the CoS declares a priority per package; the
  deterministic manager validates it; the broker enforces pickup order.
  *(decided, M1; encoding — OQ1)*
- **Parallel submission:** independent packages run concurrently (default
  5 agents in flight, per-project configurable); dependent packages are
  held in the CoS backlog until upstream reports return. *(decided, M1)*
- **Change management:** information arriving mid-run is classified —
  additive (held for future packages) or corrective (a follow-on revision
  package after completion, referencing the prior artifact). No mid-flight
  interruption of running agents. *(decided, M1)*
- **Results aggregation:** the CoS reads every report and committed
  artifact, and answers the owner with one human answer — its rollup job.
  *(decided, M1)*
- **Conversation continuity:** backlog, open proposals, and submissions
  survive reboots; nothing approved is orphaned. *(decided, M1)*
- **Multi-project:** one project = one VM = one gateway = one resident
  CoS; the desktop registers N project connections; projects share
  nothing by default. *(decided; per-project memory scoping at the second
  project)*
- **Autonomous submit mode** — the CoS submits without per-proposal
  approval. *(trigger-gated: separately designed + gated milestone after
  M1 proves ask-before-submit)*

## 2. The execution pipeline (carried forward, V2-owned)

- **Durable orchestration core:** Temporal workflows — every task survives
  restarts, retries deterministically, and is observable in the Temporal
  UI. *(decided — proven, carried forward under the `ea-` rename)*
- **Deterministic validation:** the Go manager validates every package —
  agent exists in the catalog, executor authorized, repo target declared,
  priority/TTL in bounds. The agent proposes; the code disposes.
  *(decided)*
- **Ephemeral single-task workers:** each task = one fresh container, its
  own branch, its own scoped credential, one artifact, then destroyed —
  zero-survivors gate on every run. *(decided)*
- **Two executor harnesses:** claude-code for work whose artifact is code;
  hermes-agent for everything else — same persona files, different tooling
  environment; harness and model are independent settings. *(decided)*
- **Versioned message contract:** message-v1 evolves additively only;
  breaking changes require a versioned message-v2 with a transition.
  *(decided — standing policy)*
- **Per-project configuration surface:** a `project.yaml` manifest in the
  project repo (repo layout, concurrency scope, later model/TTL/priority
  defaults) — config as declaration, read by the CoS, validated by the
  manager. *(decided, fields accumulate as topics close)*

## 3. Work management and repo integration

- **Single-repo-per-project default; multi-repo by declaration** via the
  manifest; manager-enforced. *(decided)*
- **Safe-by-default concurrency for coders:** omitted file scope = exclusive
  (sequential same-repo); parallelism by declaration with deterministic
  manager exclusion. *(decided; scope-declaration milestone post-M1)*
- **Branch-per-task with PR-able output:** every coder task lands on its
  own branch; merging is the github-operations-specialist's or the owner's
  job. *(decided — proven)*
- **Scoped, ephemeral GitHub credentials:** per-task GitHub App token,
  issued at spawn, revoked at reap, verified even on abnormal exit;
  repository-scoped per task. *(decided)*
- **The agent organization as reusable context:** persona files, skill and
  tool definitions, and behavioral specs hydrate every worker from the
  roster repo; the llm-wiki carries prior project knowledge.
  *(decided — proven)*

## 4. Memory

- **Institutional memory:** every task's learning is available to future
  tasks at boot (Hindsight on the memory VM). *(decided — proven)*
- **Pointer-store convention:** documents live only in the project repo;
  memory holds pointers; the repo carries its own history index. No
  component owns a second copy of a document. *(decided)*
- **Semantic recall (embeddings):** meaning-based retrieval over memory
  pointers. *(trigger-gated: built only if pointer recall proves poor —
  small self-hosted model on the memory VM, no new credential class)*

## 5. Security and isolation

- **Isolation ladder with written tripwires:** containers → rootless
  runtime + per-executor network segmentation → syscall-sandbox →
  per-task micro-VM; each rung is its own gated milestone, each trigger
  checkable. *(decided; rung A at M1, A+ immediately after)*
- **Registry transport integrity:** TLS + internal CA + basic auth +
  digest-pinned image pulls — the image supply chain can't be poisoned in
  transit. *(decided — build-start gated item)*
- **Service authentication:** caller tokens on the llm-proxy (with spend
  caps and per-task attribution) and Hindsight (write/read split); memory
  API restricted to the machines that need it. *(decided — build-start
  gated items)*
- **Least-privilege CoS:** the resident agent holds no GitHub token, no
  queue access, no registry write — asserted positively (capability check)
  and negatively (env check) at the gate. *(decided)*
- **Approval-payload integrity:** the exact behavioral spec the owner
  approved is hash-pinned; the submitted package cannot differ from it.
  *(decided, M1)*
- **Submit-side audit trail:** every proposal/submit/hold/escalation
  logged; CoS behavior is observable and reviewable post-incident.
  *(decided — minimum observability set)*
- **Secure key management (vault)** on the front-of-house VM as the
  credential-issuing authority. *(deferred at owner direction; baseline
  recorded)*
- **Production hardening list:** gateway TLS beyond LAN trust, multi-host
  execution, multi-tenancy, rate limiting. *(deferred — the trust-boundary
  arc with key management)*

## 6. Operations

- **Reboot-surviving stack:** dependency-ordered restart baked into the
  build artifacts — not a documented manual procedure. *(decided)*
- **Contract test suite:** reusable boundary tests (spawn-env, message
  schema, catalog shapes) built with or ahead of the first milestone —
  including negative cases. *(decided)*
- **File-level impact inventory:** every build/deploy/install file
  enumerated and mapped to the decision it serves before the first
  milestone runs; gates assert against it. *(decided)*
- **Gated milestones with signed evidence:** every feature lands through
  its own test procedure, signed under the owner's authority, in the V2
  decision-log + issue-ledger record. *(decided — standing rule)*
- **Upstream dependency refresh policy:** pinned CLIs/images with a
  refresh cadence, digest-bump discipline, and exception expiry.
  *(queued — queue item 6)*
- **Registry housekeeping:** retention/GC policy and disk alerting on the
  registry VM. *(queued — with the refresh policy)*
- **Dedicated V2 demo repo** (`ephemeral-v2-demo`) as the coder target,
  with the GitHub App installed when coder-style work arrives.
  *(decided — GitHub-side item)*
- **Llm-wiki curation automation** beyond the owner's append-only cadence.
  *(queued — queue item 5)*
- **Model specification & configurables:** per-agent model pinning, TTL
  defaults, executor fields in the catalog — one declarative resolution
  chain. *(queued — reset topic, restarts from scratch)*

## 7. Documentation offer

- **V2 design set** (M1 design + platform design + this list + the review
  report) — the full reasoning, decided vs. deferred, in the repo.
- **V2 issue ledger + closing findings report** — every issue found
  during the build, symptom → wrong assumption → root cause → the rule
  we now follow. *(decided — closing deliverable)*
- **The V2 book** — written last, after the full installation/deployment
  is proven working, containing V2's findings and corrective actions from
  the record. *(decided — closing deliverable)*

## The one-line offer

> Ask your company's work in plain language; a resident chief-of-staff
> decomposes it, proposes the plan, waits for your approval, and runs it
> through a gated pipeline of ephemeral AI specialists who work in
> parallel, on real repositories, with scoped credentials, institutional
> memory, and a durable, auditable record — where every agent proposes
> and only verified code disposes.
