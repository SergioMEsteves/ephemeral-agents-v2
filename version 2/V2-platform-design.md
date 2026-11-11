# V2 Platform Design — naming, memory, isolation, and carried-forward lessons

> Status: DRAFT v1, 2026-11-10. This document records the platform-level
> decisions that sit outside (and outlive) the V2-M1 Chief-of-Staff milestone:
> the V2 naming family, the memory architecture, the concurrency default,
> the embeddings stance, the queue-evolution policy, the isolation ladder,
> and the V1 lessons that the V2 build pre-applies. Companion to
> `V2-M1-cos-design.md`. Every decision here was made with the owner on
> 2026-11-10 and is cross-referenced in `../decision-log.md`.

## 1. V2 naming family (retire "poc")

V2 is a production-bound iteration, not a proof-of-concept. All V2-owned
components use the **`ea-` naming family** (ephemeral-agents):

| Component | V1 name | V2 name |
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
- **The baseline-synced `deploy/` tree keeps V1 names until that build
  action lands** — it is verbatim V1 evidence (the signed M0–M5 gate runs
  reference those exact names), and renaming it silently would break
  traceability to the V1 record.
- **From the build action onward, V2 design docs reference only V2
  names.** V1 components carried forward unchanged (e.g. VM-Xb's stack)
  are stated once, as provenance ("carried forward from the V1 baseline @
  `4de7a06…`"), and thereafter referred to by their V2 names.
- The runtime choice per project (docker vs. podman) joins the
  configuration topic (§7 of `V2-M1-cos-design.md`) as a manifest-declared
  field.

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
   layer on top; the repo is the durable, pullable record.
4. **The store stays on the memory VM.** It already serves every executor
   (V1's hydration contract: `/memory/read` at boot, logged as
   `M4_MEMORY_HYDRATE`) and outlives VM rebuilds. The CoS writes through
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
- V1 open item "long-term queue shape / concurrency beyond sequential"
  narrows to estate worker-capacity tuning (env values, not code) once
  parallel submission becomes the norm (OQ3 in the M1 design doc).

## 4. Embeddings provider — evidence-driven (owner, 2026-11-10)

- **No provider is chosen upfront.** M1 builds with the current
  zero-vector fallback (`EMBEDDINGS=none`, NaN-safe scoring, proven in V1
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
   optional fields (like `priority`, the first one) with safe defaults;
   consumers must tolerate fields they don't know.
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

What V1 already provides and carries forward unchanged — all *operational*
protections: scoped per-task GitHub App tokens issued at spawn and revoked
at exit, TTL-bounded lifetimes, the zero-survivors reaper as a hard gate,
registry-pinned image sourcing. The ladder below adds *architectural*
protections.

### The ladder

| Rung | What it is | Pros | Cons | Adopt when |
|---|---|---|---|---|
| **A — co-located containers** (V1 status quo, M1) | Docker container per task on the shared `ea-net` (renamed from V1's network), alongside broker, Temporal, worker, llm-proxy | Zero new work; proven M0–M5; fastest spawn (~800 ms); cheapest; whole toolchain signed against it | Shared host kernel; root Docker daemon present; executor can reach internal services on the network; cleanup is enforced promise, not physical guarantee | Default for M1 |
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

## 7. V1 lessons pre-applied in the V2 build

The V2 build follows the V1 build process (M0-style stages, gated
milestones, signed evidence) with every V1 lesson structurally present
from the start. Each lesson maps to the concrete V2 build step that
embodies it; during the build we verify the lesson is structurally
present, not remembered:

1. **Nothing load-bearing lives only on a VM** (V1: the `/tmp` llm-proxy
   loss costing a full re-run) → every runtime artifact, mount source,
   and config is canonical in the repo before the build starts; the V2
   llm-proxy mounts from a durable host path staged from the repo.
2. **Contract tests before gates, not during them** (V1: each boundary
   bug cost a full ~10-minute install re-run) → the reusable contract
   test suite (spawn-env, message-v1, catalog shapes) is built with or
   ahead of M1, replacing V1's per-milestone scripts.
3. **Gate assertions name the artifact they prove** (V1: the run-16
   "artifact chain verified" paper-over) → every V2 gate assertion
   states the artifact or state that evidences the claim; §4-style gates
   fail unless report status is success.
4. **Harness-verified ≠ integration-verified** (V1: M4's direct-spawn
   gates masked a lifecycle-path bug) → V2 gates run through the real
   gateway → manager → queue → spawn path.
5. **Reboot survival is baked, not documented** (V1: host-reboot
   incident, worker crash-loop on Temporal DNS) → dependency-ordered
   restart (`restart: unless-stopped` / umbrella compose) is part of the
   V2 build artifacts, not a manual §14.8-style procedure. (Queue item 7.)
6. **Registry-pinned, no-pull image sourcing** (V1: the rmi-first proof)
   → carried forward unchanged, now under `ea/` image names from the V2
   registry.
7. **Secret-scan and zero-survivors stay hard gates** (V1: both caught
   real issues) → unchanged in every V2 gate.
8. **Pin + track upstream releases with exception expiry** (V1: §6
   trivy/bundled-dep story) → the dependency-refresh policy (queue
   item 6) applies from the first V2 image build, not retroactively.
9. **The envelope is self-sufficient + entrypoint guards** (V1: truncated
   prompt bug; `$TASK_PROMPT` under `set -u`) → V2 executor entrypoints
   guard every env reference and hydrate the full contract (persona,
   wiki, memory) before work begins.
10. **Inventory-first for the estate** (V1: the "moving floor" lesson —
    pin VMIDs/IPs in one committed inventory from minute one) → the V2
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
