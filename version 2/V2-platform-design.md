# V2 Platform Design — naming, memory, isolation, and carried-forward lessons

> Status: DRAFT v1, 2026-11-10. This document records the platform-level
> decisions that sit outside (and outlive) the V2-M1 Chief-of-Staff milestone:
> the V2 naming family, the memory architecture, the concurrency default,
> the embeddings stance, the queue-evolution policy, the isolation ladder,
> and the lessons the build pre-applies. Companion to
> `V2-M1-cos-design.md`. Every decision here was made with the owner on
> 2026-11-10 and is cross-referenced in `../decision-log.md`.

## 1. V2 naming family (retire "poc")

V2 is a production-bound iteration, not a proof-of-concept. All V2-owned
components use the **`ea-` naming family** (ephemeral-agents):

| Component | pre-rename estate name | ea name |
|---|---|---|
| Container network | `poc-net` | `ea-net` |
| Executor images | `poc/hermes-ephemeral:1.0.0`, `poc/claude-coder:1.0.0` | `ea/hermes-ephemeral`, `ea/claude-coder` |
| Env prefix | `POC_*` (`POC_NETWORK`, `POC_EXECUTOR_DEFAULT`, `POC_IMAGE_HERMES`, …) | `EA_*` |
| Container / queue names | `poc-*` | `ea-*` |

Rules:

- **Decided now, executed at build start.** The rename is a mechanical,
  gated change to `services/` (env wiring) and the V2 compose/deploy layer,
  plus registry re-tag/re-push of the executor images. It is the *opening
  action of the V2 build phase*, not a retroactive edit.
- **The pre-rename evidence baseline is preserved in the owner's archive,
  not in this repo** — the signed M0–M5 gate runs reference those exact
  estate names, and this repo carries the ea-named deploy layer only.
- **From the build action onward, V2 design docs reference only V2
  names.** Components carried forward unchanged (e.g. VM-Xb's stack) are
  stated once, as provenance ("carried forward from the baseline build"),
  and thereafter referred to by their V2 names.
- The runtime choice per project (docker vs. podman) joins the
  **configuration topic's agenda** — the per-project manifest surface
  (M1 design §10); its field structure is undecided (the topic was reset
  at owner direction) and will be declared when that topic closes.

## 2. Memory architecture — the pointer-store convention

Three pieces, deliberately separated (owner-confirmed 2026-11-10):

| Piece | What it is | Where it lives |
|---|---|---|
| **The writer** | The agent that finished the work and decides what deserves a memory entry | The CoS on VM-Xa |
| **The store** | Hindsight (API + Postgres/pgvector) holding pointer entries only | The memory VM (`:8081`) |
| **The content** | The actual reports/documents | The project repo (sole source of truth) |

Decisions:

1. **Documents live only in the project repo.** Reports, findings, and
   analysis artifacts are committed to the repo (layout declared per the
   §10 manifest in `V2-M1-cos-design.md`); the git structure is decided
   by the project. No component holds a second copy.
2. **Memory stores pointers, never content.** A Hindsight entry records
   that work happened, what it was about, and where the artifact lives
   (repo path / report reference). A pointer cannot go stale the way a
   memory-held copy would, because the repo is always current truth.
3. **The pointer also lives in the repo itself.** The project repo
   carries its own history index (e.g. a `docs/history/` index or report
   registry committed alongside each artifact). Hindsight is the semantic
   layer on top; the repo is the durable, pullable record. *Caveat (per
   the 2026-11-10 review): pointers can dangle if an artifact is moved,
   deleted, or a branch pruned — a known cost of pointer stores, mitigated
   by the repo's own history index and by git history itself.*
4. **The store stays on the memory VM.** It already serves every executor
   (the hydration contract: `/memory/read` at boot, emitted wrapped in
   `BEGIN/END UNTRUSTED MEMORY` markers per D-mem-governance — hydrated
   entries are untrusted data with per-entry provenance (`task_id`,
   `agent_ref`, `created`), subject to the 90-day staleness
   re-validation rule, and load-bearing conventions enter the store only
   through the CoS's roll-up writes) and outlives VM rebuilds. The CoS writes through
   the same API the executors already read.
5. **Flow:** memory surfaces a pointer ("relevant past work exists, here
   is where to look") → the CoS or executor pulls the actual document from
   the repo when detail is needed.

## 3. Multi-flow concurrency — default 5, configurable (owner, 2026-11-10)

- The parallel-capacity default is **5 ephemeral agents in flight**,
  configurable per project. It is a configuration-topic candidate for the
  per-project manifest (`max_parallel_agents`, design §10).
- **Scope note:** the count applies to ephemeral executor agents.
  Same-repo coding tasks remain sequential in M1 by design (V2-M1 design
  §11); the 5-slot default takes full effect when the scope-declaration
  milestone enables same-repo parallelism. Cross-repo and cross-type work
  can use the slots immediately.
- The pre-build open item "long-term queue shape / concurrency beyond sequential"
  narrows to estate worker-capacity tuning (env values, not code) once
  parallel submission becomes the norm (OQ3 in the M1 design doc).

## 4. Embeddings provider — evidence-driven (owner, 2026-11-10)

- **No provider is chosen upfront.** M1 builds with the current
  zero-vector fallback (`EMBEDDINGS=none`, NaN-safe scoring, proven in the
  M4/M5 gates).
- **Trigger:** if recall of memory pointers proves poor in practice
  (missed relevant past work), plug in a small self-hosted embeddings
  model on the memory VM — behind the same one-service-owns-the-provider
  pattern as the llm-proxy (self-hosted = no new credential class, LAN-
  internal, zero marginal cost). The pgvector side of Hindsight is already
  deployed and waiting; the embeddings model is the only missing piece.
- **Demoted from** "pick infrastructure now" to "measure, then decide."
  Any choice when triggered joins the configuration topic
  (`EMBEDDINGS=none | <provider>` per project).

## 5. Queue shape — additive-evolution policy (owner, 2026-11-10)

Recorded as a standing policy rather than a design project:

1. **message-v1 stays the contract.** Changes are additive only: new
   optional fields (like `priority`, the first one) with safe defaults.
   *Corrected per the 2026-11-10 review* — the seeded schema is
   `additionalProperties: false`, so "consumers tolerate unknown fields"
   is **not** how it works. The actual mechanics: an additive field is
   added to `schemas/message-v1.json` itself as an optional property with
   a documented default (absent = default behavior); validators are
   updated in the **same gated change** as the consumer-side support
   (e.g. the manager pass-through); and consumers validate against the
   current schema version — which is exactly why a field and its
   consumers must land together. The schema's original "POC task message"
   title is corrected at the same first touch. This was the review's
   first exercise of this policy: the policy and the schema as seeded
   were contradictory, and the record above supersedes the earlier
   wording.
2. **Breaking changes trigger a proper message-v2** — a version field in
   the message header and a documented transition. No ad-hoc edits to
   meaning.
3. **Topic topology stays as-is** (one task topic, capability-routed)
   until a genuinely new message type is needed (e.g. cancellation,
   progress streaming); each new type is designed as its own small gated
   addition.
4. **The CoS never touches the broker directly** — it determines priority
   and parallelism through the order and content of its gateway
   submissions; the manager validates and applies (V2-M1 design, D9 and
   the prioritization decisions).

## 6. Isolation level — a ladder with tripwires (owner, 2026-11-10)

**Decision: stay on the proven container-per-task architecture for M1;
adopt the first hardening rung (rootless runtime + network egress
allow-list) as a small separately-gated change immediately after M1's
gate; record gVisor-class sandboxes and per-task micro-VMs as
trigger-gated future rungs, not current work.**

Operating context this decision assumes (owner-stated): single company,
inside the company security boundary; all task content originates from
the owner; executors perform code development, business analysis,
research, and other major company work; 5 concurrent agents on own
hardware.

What the estate already provides and carries forward unchanged — all *operational*
protections: scoped per-task GitHub App tokens issued at spawn and revoked
at exit, TTL-bounded lifetimes, the zero-survivors reaper as a hard gate,
registry-pinned image sourcing. The ladder below adds *architectural*
protections.

### The ladder

| Rung | What it is | Pros | Cons | Adopt when |
|---|---|---|---|---|
| **A — co-located containers** (the estate status quo, M1) | Docker container per task on the shared `ea-net` (renamed from the first organization's network), alongside broker, Temporal, worker, llm-proxy | Zero new work; proven M0–M5; fastest spawn (~800 ms); cheapest; whole toolchain signed against it | Shared host kernel; root Docker daemon present; executor can reach internal services on the network; cleanup is enforced promise, not physical guarantee | Default for M1 |
| **A+ — rootless runtime + egress allow-list** (adopt post-M1) | Rootless Podman (or Docker rootless mode): no root daemon; plus per-task network rules — executors reach only the project repo, the llm-proxy, and the registry | Removes the worst failure mode (escape → root daemon → own the execution VM); worst case per bad task becomes contained + unprivileged + TTL-reaped; closes the missing lateral-network layer (no legitimate reach to broker/DB/memory VM); near drop-in (same images, same CLI verbs) | Real but small lifecycle code change (Docker API → rootless flow); executor gates re-verified under the new runtime before re-signing; ~10–20% overhead for gVisor-class options avoided but rootless has its own volume/uid quirks | **Immediately after M1's gate** — first V2 hardening change, own gated milestone |
| **B — gVisor-class sandbox** (gVisor/`runsc`, sibling: Kata) | Container syscalls intercepted by a user-space kernel; ~200 of ~300 syscalls unavailable; escape hits a software barrier, not the real kernel | Closes kernel escape without changing any workflow element (runtime flag swap); invisible to the contract (message-v1, manager, TTL, credentials unchanged); moderate overhead (10–20% CPU, slower I/O) | Compatibility risk with executor internals (git, node, CLI processes) — breakages look like random harness failures; new pinned runtime to maintain (dependency-refresh item); no network isolation by itself | When task content can originate outside the owner's control (external contributions, third-party work packages, unvetted data sources) |
| **C — per-task micro-VM** (Firecracker / Kata / small QEMU) | Each task gets its own tiny VM: separate kernel, separate virtual network; container runs inside its own machine | Strongest wall available; a compromise cannot see or reach any other task or the estate services even in principle; makes zero-survivors physical ("destroy the VM"); natural network isolation | Heaviest (~128 MB+ RAM, seconds of boot per task — strains the 5-agent default on current sizing); largest engineering surface (VM provisioning path, image pipeline, every gate re-validated); disproportionate while all task content is owner-originated | When the estate serves anyone other than the owner, or any execution crosses the company boundary |

### Policy

- **It's a ladder, not a one-time pick.** Each rung defends a different
  layer: engine (A+) → sandbox (B) → machine (C). Nothing about A/A+
  prevents upgrading later.
- **Triggers are written, checkable, and standing.** The security posture
  escalates when the trust model actually changes; nobody re-litigates
  from scratch.
- **Network egress allow-lists layer onto every rung** and are the
  highest importance-per-dollar gap today (executor containers currently
  have no reason to reach the broker, Temporal's Postgres, or the memory
  VM).
- **Isolation escalations ride the same gate discipline as everything
  else:** each rung adoption is its own milestone with its own test
  procedure and signed evidence.

## 7. Lessons pre-applied in the build

The build follows the staged build process (M0-style stages, gated
milestones, signed evidence) with every lesson structurally present
from the start. Each lesson maps to the concrete V2 build step that
embodies it; during the build we verify the lesson is structurally
present, not remembered:

1. **Nothing load-bearing lives only on a VM** (the `/tmp` llm-proxy
   loss costing a full re-run) → every runtime artifact, mount source,
   and config is canonical in the repo before the build starts; the
   llm-proxy mounts from a durable host path staged from the repo.
2. **Contract tests before gates, not during them** (each boundary
   bug cost a full ~10-minute install re-run) → the reusable contract
   test suite (spawn-env, message-v1, catalog shapes) is built with or
   ahead of M1, replacing per-milestone scripts.
3. **Gate assertions name the artifact they prove** (the run-16
   "artifact chain verified" paper-over) → every gate assertion
   states the artifact or state that evidences the claim; §4-style gates
   fail unless report status is success.
4. **Harness-verified ≠ integration-verified** (M4's direct-spawn
   gates masked a lifecycle-path bug) → gates run through the real
   gateway → manager → queue → spawn path.
5. **Reboot survival is baked, not documented** (the host-reboot
   incident, worker crash-loop on Temporal DNS) → dependency-ordered
   restart (`restart: unless-stopped` / umbrella compose) is part of the
   build artifacts, not a manual §14.8-style procedure. (Queue item 7.)
6. **Registry-pinned, no-pull image sourcing** (the rmi-first proof)
   → carried forward unchanged, now under `ea/` image names from the
   registry.
7. **Secret-scan and zero-survivors stay hard gates** (both caught
   real issues) → unchanged in every gate.
8. **Pin + track upstream releases with exception expiry** (the §6
   trivy/bundled-dep story) → the dependency-refresh policy (queue
   item 6) applies from the first image build, not retroactively —
   and under digest-pinned sourcing, a CVE refresh is an explicit
   **digest bump + re-sign**, recorded so it isn't misread as breakage
   (second-pass review).
9. **The envelope is self-sufficient + entrypoint guards** (the truncated
   prompt bug; `$TASK_PROMPT` under `set -u`) → executor entrypoints
   guard every env reference and hydrate the full contract (persona,
   wiki, memory) before work begins.
10. **Inventory-first for the estate** (the "moving floor" lesson —
    pin VMIDs/IPs in one committed inventory from minute one) → the
    build's chassis stage re-runs its gate against the committed
    inventory; a fresh build catches inventory-vs-reality mismatch at
    minute five, not three stages deep.

## 8. Where the remaining items live

Isolation (this doc, §6) was queue item 3; its *decision* is made; its
**A+ implementation** becomes a build-phase milestone after M1. Queue
item 4 (embeddings) is resolved as policy (§4). Queue item 1 (model
specification & configurables) restarts from scratch at owner direction;
the runtime/docker-vs-podman field and `max_parallel_agents` join its
agenda (configuration topic). Items 2, 5, 6, 7, 8, 9 remain as queued.

## 9. Design review 2026-11-10 — findings application (owner-accepted)

The full end-to-end design review (enterprise architecture, software
engineering, network engineering, security architecture, SRE — 28
findings) was accepted by the owner. Its applications are already in the
docs: M1 design §4 (manager-change enumeration), §5 (enforcement honesty),
§6 (state persistence mechanism + completed failure behaviors), §7
(assertions 9–12, judgment corpus, OQ4-conditioned assertion 3); §5 above
(schema-evolution mechanics), §2 (pointer-dangling caveat). This section
records the applications that live here.

### 9.1 Security controls pulled forward (not the deferred key vault)

*Staging note (second-pass review): these controls create new secrets
(registry basic-auth, llm-proxy tokens, Hindsight tokens) while the key
vault is owner-deferred — each gated item below must name where its
secrets are staged (gitignored env files, 0600) and their rotation
expectation, so the deferral of the vault does not leave the new
credentials homeless.*

1. **Registry transport integrity (review critical):** the registry VM's
   `:5000` gets TLS (internal-CA cert) + basic auth, and executor images
   are pulled **by digest** (`ea/hermes-ephemeral@sha256:…`) with digest
   re-verification in the lifecycle spawn path. Tag-pinning is not
   integrity without transport integrity. Fallback if TLS is blocked:
   pre-stage images on VM-Xb and firewall the registry VM to lifecycle
   only. Small gated item at build start — not the deferred vault.
   Includes (second-pass review): the **credential-distribution story**
   for the registry basic-auth (who holds it, where staged — it is a new
   secret and joins the staging note below) and a **retention/GC policy**
   on the registry (keep-last-N per tag, disk alert) so digest-pinned +
   no-pull sourcing doesn't become an unbounded disk-growth failure.
2. **llm-proxy caller auth:** static per-consumer-class token (executors
   vs CoS), bind/allow-list restriction, per-token spend/rate cap, and
   per-token usage logging — plus **per-task attribution** (the lifecycle
   injects the task_id as a request header) with per-container rate caps,
   so spend anomalies are attributable to a task, not just a class
   (second-pass review). The CoS's LLM calls go through the llm-proxy
   with the CoS-class token — the highest-spend actor is inside the cap
   and logging perimeter. *Attribution is advisory only (third-pass
   drift pass):* the task_id header the lifecycle injects can be spoofed
   by a compromised executor (it controls its own HTTP stack) — it is
   observability, not identity; the enforceable per-container caps key
   on the token + container identity, with an aggregate per-token cap
   backstop.
3. **Hindsight auth + reach restriction:** **token split** (second-pass
   review decision) — a CoS-class **write** token and an executor-class
   **read-only** token, so a compromised executor cannot poison the
   memory pointers the CoS later reads as trusted context; Postgres TLS
   or container-only bind; Proxmox-firewall restriction of `:8081` to
   VM-Xa (CoS writes) and VM-Xb (executor-side reads); pointer
   provenance (writer task id) recorded per entry.
4. **Dashboard compensating control (within the owner's LAN-open
   decision):** the worker verifies a publisher-identity/HMAC field so
   UI-published messages are distinguishable from manager-validated ones,
   and/or the UIs are bound to the owner's workstation interface — the
   owner states which at build start. *Change-surface note (second-pass
   review):* the in-band HMAC option is an additive message-v1 field and
   must land in the schema in the same gated change as the worker-side
   verification (per §5's corrected rule); the interface-binding option
   touches no schema.
5. **GitHub App token custody (rung A):** token mounted as a 0600 tmpfs
   file rather than env where feasible; revocation-at-reap asserted even
   on abnormal exit; per-task-repo scope confirmed (project A's token
   useless against project B); sibling-token exposure recorded as an
   explicit accepted residual of rung A, closed at A+.

### 9.2 A+ rung re-specified (review major): two separable pieces

Rung A+ is **(1) lateral segmentation** — each executor (or task pair) on
its own small bridge network whose only egress is an allow-listing
forwarder/proxy (registry, llm-proxy, github.com only — no broker,
Temporal/Postgres, lifecycle, or memory VM reach; this closes the
executor→broker publish path that would bypass the manager), and
**(2) rootless runtime** (Podman/Docker-rootless — daemon-escape
containment). The A+ milestone gate asserts **both**; a rootless swap
alone does not pass. This supersedes the single-piece description in §6.

**Memory hydration under A+ (decided, second-pass review):** the §9.2
allow-list ("registry, llm-proxy, github.com only") conflicts with the
hydration contract (executors read Hindsight `:8081` at boot). The
decision: **hydration moves spawn-side at A+** — the lifecycle
pre-fetches the memory bundle (with the executor-class read-only token)
and mounts it into the executor. The executor never needs memory-VM
reach (stronger isolation, consistent with pointers-only); the CoS keeps
its own restricted read/write path. **A+ gate re-verification list
(third-pass drift pass):** the change touches the `M4_MEMORY_HYDRATE`
marker's semantics, the executor entrypoint's hydration path, and gives
the lifecycle a new credential custodianship (the executor-class
read-only token — it joins §9.1's staging note); all three are named
re-verification items of the A+ gate. **Degraded-mode rule:** Hindsight
unreachable at spawn ⇒ the spawn **fails** (or proceeds without
hydration only if explicitly logged as degraded) — never silently
without memory. The forwarder is also a **monitored
single point of failure** — all in-flight executors stall if it dies;
monitor it and document the degraded-mode behavior in the A+ runbook.

### 9.3 Capacity and observability (review majors)

- **Capacity model before the 5-agent default is trusted:** per-executor
  RSS ceiling, VM-Xb RAM/CPU headroom, a 5-concurrent soak test as gate
  evidence, per-container memory limits encoded so executors die before
  Temporal/Postgres, and OQ3 (worker concurrency) tuned to measured
  numbers. If the VM cannot hold 5 concurrent coders comfortably, the
  manifest default becomes the measured safe value, not the aspirational
  5.
- **CoS observability (minimum viable)** — with the audit-trail
  provenance split made explicit (third-pass drift pass): the **tracker
  master-plan history is the intent trail**, the **local board history
  is working intent**, and the **gateway/manager logs are the
  enforcement trail** (what was actually submitted and validated — the
  only source that isn't self-attested by the CoS). Every
  proposal/submit/hold/escalation event as a structured line in a
  persistent VM-Xa log; whether the unchanged gateway already emits
  sufficient submit-side logs is a **build-time verification item**
  (cited if yes, enumerated as a change if no). A daily/on-demand CoS
  status rollup (open proposals, backlog depth, in-flight, last submit)
  as part of its documented duties; session-transcript retention for
  post-incident review. No dashboards — a log file and a status verb
  suffice for one owner-operator.

### 9.4 Scaling honesty (review major)

D6 (one project = one VM-Xa) **supersedes** the 2026-11-08 "no new VM"
note for multi-project growth — recorded explicitly in the decision log
with the D6 rationale. Hindsight per-project scoping (the scope key on
the shared memory VM) is named when the first second project arrives;
per-project gateway token lifecycle is stated then. Single-project M1 is
unaffected.

### 9.5 Build-phase file-level impact inventory (owner directive)

**Before the first V2 milestone runs**, the build phase opens with a
committed **file-level impact inventory**: every file required for a full,
clean V2 build, deployment, installation, and all checks — enumerated and
mapped to the decision/condition it serves. Minimum coverage:

- compose files (all milestones' stacks) and their env var wiring
  (`POC_*` → `EA_*` rename surface, network rename `poc-net` → `ea-net`);
- Go services (`services/`): env parsing, validation logic, queue/repo
  wiring touched by the M1 conditions;
- executor entrypoint scripts and Dockerfiles (hydration contract,
  entrypoint guards, tmpfs token mount, digest-pinned pulls);
- queue definitions (the OQ4 `x-max-priority` redeclare), registry
  configuration (TLS/auth), and lifecycle spawn path;
- the schema (`schemas/message-v1.json`) and its validators;
- hosts/env inventory files (gitignored) and the committed inventory
  mapping;
- **the endpoint/flow table** (second-pass review): component → outbound
  endpoints (name, port, auth) → why — for every component including the
  CoS; it is the specification the A+ allow-list, the credential
  capability assertion, and the L2 analysis all assert against. It must
  include the **cross-VM CoS dependency** introduced by the CoS routing
  its LLM calls through the llm-proxy on the execution VM (third-pass
  drift pass): front-of-house CoS reasoning degrades when VM-Xb is down
  — stated, with the proxy's bind/allow-list admitting VM-Xa.

Each entry names: file → change → decision/finding it serves → which
milestone/gate exercises it. This inventory is the artifact the rename
micro-gate and every subsequent gate assert against — gate assertions
name the artifact they prove (platform lesson §7.3), starting here.

### 9.6 The build process (staged process, this build's record)

The build reproduces the staged process end-to-end, with its own record:

- **Staged build (M0-style):** estate chassis → broker/engine →
  services → executors → memory/wiki → front-of-house → smoke, each
  stage with a passing check before the next; `--check-only` dry-run
  against the committed inventory before provisioning.
- **Milestones with their own test procedures and gates:** nothing lands
  ungated (the gate rule); the M1 design doc's TP-V2-M1
  (with review additions) is the first.
- **V2 issue ledger:** every issue found during the V2 build is recorded
  in V2's documentation in the standard format — *symptom → wrong assumption →
  root cause → the rule we now follow* — via the decision log and/or the
  closing report, so the build's corrective actions are part of its own
  record (not folded silently into the carried lessons).
- **Signed TP results** per milestone under the same sign-off authority.
- **Closing findings report** for the V2 build, plus per-milestone
  evidence under the V2 deploy tree (gitignored per convention).
- **The V2 book comes last** (owner decision 2026-11-10): after the
  full installation/deployment is proven working, so the V2 edition
  includes everything the build actually found — issue ledger,
  corrective actions, measured numbers, gate evidence — written from
  the record, not predicted before the fact.
- **Contract test suite built with or ahead of M1** (platform §7.2) — a
  named prerequisite artifact of TP-V2-M1, including schema-negative
  cases (out-of-range priority, manifest-missing repo_target, unknown
  field under the current schema).

### 9.7 Rename execution order (review minors)

1. **The rename completes before any OQ4 queue work** (RabbitMQ queues
   do not survive renames; the x-max-priority redeclare happens once,
   under the final `ea-*` name).
2. The rename is its own **micro-gate**: `grep -ri poc` over services/ +
   compose returns only provenance citations — the grep is scoped to the
   V2-owned trees, with a stated whitelist for the committed estate→ea
   mapping table (which itself contains `poc` strings by design); the
   estate's baseline test path re-runs green under `ea` names; registry
   re-tag verified by **digest equality** with the pre-rename images
   (rename without rebuild); one committed estate-name → ea-name mapping
   table for evidence cross-referencing.
3. Post-rename, the affected structural assertions re-run under `ea`
   names before any new feature lands.
