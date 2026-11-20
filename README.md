# ephemeral-agents-v2

An organization of AI agents that runs real work on real hardware: durable
orchestration, a role roster, ephemeral single-task workers, scoped
credentials, and institutional memory. A human talks to the system in
conversation; the system turns that conversation into approved work
packages, executes each one in an ephemeral container that gets a real
token, does the work against a real repo, writes a report, and disappears —
leaving zero survivors. The manager (deterministic Go, never an agent) is the
contract-enforcer; the agent proposes, the code disposes.

## Architecture

```
desktop (conversation)
   │
   ▼
Chief-of-Staff (resident Hermes agent, VM-Xa)
   │  proposes work packages
   ▼
gateway (ea/gateway, VM-Xa :8083)
   │
   ▼
manager (ea/manager — deterministic Go: validates every proposal
   │      against the roster index, schema, and manifest)
   ▼
queue (RabbitMQ on VM-Xb: ea-tasks → topic-bridge → Temporal workflows)
   │
   ▼
executors (ephemeral containers on VM-Xb: ea/hermes-ephemeral,
   │        ea/claude-coder — hydrate persona/wiki/memory, scoped
   │        per-task GitHub token, revoked at reap)
   ▼
reports (/reports/<task_id>.json — outcome + artifact pointer)
```

Supporting services: lifecycle + worker (spawn/reap, response publishing),
hindsight memory (pgvector store on the memory VM, pointer-store convention),
llm-proxy (model calls with per-class tokens and spend caps), private
registry (digest-pinned image sourcing). Isolation ladder: co-located
containers now (zero-survivors enforced), rootless + egress allow-list as a
gated follow-up, sandbox rungs trigger-gated.

## Getting started

- **Collect your inputs first:** `deploy-v2/INSTALL-INPUTS-CHECKLIST.md` —
  every account, key, address, and decision you need before the first build
  step, with stop conditions.
- **Read the book:** `version 2/book/` — the system in plain language: the
  architecture, the work order, the executors, the front door, two
  organizations on one estate, building from scratch, and the Evaluator's
  Guide.
- **Deploy:** `deploy-v2/RUNBOOK-V2-BUILD.md` — the staged build from a bare
  PVE host: chassis (m0) → adapter (m1) → lifecycle (m2) → executors (m3) →
  memory (m4) → front-of-house + CoS (m5), each stage gated before the next.
  Have your Desktop agent run it for you by installing the
  `deploy-v2/skills/ea-install/` skill (book Special 4).
- **Onboard a project:** `deploy-v2/RUNBOOK-V2-NEW-PROJECT.md` — the
  template-onboarding flow (ADR-0002).

## Repo layout

```
version 2/            design record + book (M1 CoS design, platform design,
  book/               impact inventory, issue ledger, ADRs under version 2/)
deploy-v2/            the deploy layer: m0–m5 installs + gates, runbooks,
                      contract tests, rename script, security staging
services/             Go modules (manager, topic-bridge, lifecycle, worker,
                      hindsight-api, gateway source)
schemas/              message contract (schemas/message-v1.json — the task
                      envelope; evolves additively, field+consumer same change)
WORKING-STATE.md      living continuity (current state, decisions, next actions)
decision-log.md       append-only decisions (date, rationale, rejected alternatives)
```

## Honest status

**Proven (gated, signed evidence in `deploy-v2/m*/evidence/`):**

- The full pipeline end to end: conversation → work package → ephemeral
  executor → report, zero survivors (M0–M5 gates all PASS).
- Ephemeral execution with real work: clone → edit → commit → push on a
  live repo; scoped per-task token issued and revoked (verified dead).
- Coexistence on one estate: the neighboring first-organization stack and
  this build run side by side with distinct compose namespaces, queues,
  volumes, and ports; the queue-direct publish fix removes the first-start
  race between the two bridges.
- Memory: fresh pgvector store, hydration contract, pointer-store
  convention; isolation between the two organizations' stores verified.
- Failure paths: crash recovery with an independent reaper (the
  load-bearing test), timeout TTL clamp, restart-durable stack, token
  revocation race closed.

**Designed but not yet built (tracked in `version 2/V2-gap-analysis.md`):**

- The CoS itself is the current milestone: its design is complete and
  reviewed, its runtime is not yet deployed.
- Rootless execution + egress allow-list (isolation rung A+), digest-pinned
  spawn path re-verification, capacity model + soak test, key vault,
  embeddings provider decision, dependency refresh pipeline, multi-project
  template onboarding (ADR-0002 shape decided, not built).

## Authorship

Concept, designs, and specifications: Ronald A Steinhauer — A&R Visual
Development Inc (conceived May 13, 2026); AI served as research assistant
and rules-bound implementer. See [AUTHORSHIP.md](AUTHORSHIP.md).

## License & notices

- [LICENSE](LICENSE)
- [NOTICE](NOTICE)
- [THIRDPARTY-NOTICES.md](THIRDPARTY-NOTICES.md)
