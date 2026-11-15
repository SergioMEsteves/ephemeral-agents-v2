# Chapter 15 — Evaluating the System: The Evaluator's Guide

> **In plain terms:** Everything before this chapter described the V2 build.
> This chapter is for the person who wants to prove those descriptions on the
> running estate — to submit a real request, watch it travel the queue, and
> verify each claim of the findings report against the live system rather
> than the book's word. Throughout, `<front-host>` is the front-of-house VM,
> `<execution-host>` the execution VM, and `<memory-host>` the memory VM;
> `<user>` is the deployment account. Concrete addresses, ports, and
> credentials live with the operator in the gitignored env files and are
> deliberately never printed here.

## Read this first — the POC boundary, and the V2 twist

**This is a proof-of-concept estate, twice over.** It is not
production-ready, and it must not be operated as such:

- **No authentication on the interfaces.** The V2 gateway
  (`http://<front-host>:8083`), the Temporal web UI
  (`http://<execution-host>:8080`), and the broker management plane are
  reachable per the estate's binding decisions, without credentials. The
  perimeter is the network, nothing more.
- **Container-level isolation, one execution host.** No multi-tenancy, no
  rate limiting, no scale-out. The A+ isolation upgrade (rootless +
  segmentation) is the first *change* milestone, not part of this baseline
  (Chapter 13).
- **Two organizations share the estate.** The defining V2 twist: V1's
  stacks run beside V2's on the same VMs and the same broker. Two
  consequences an evaluator must respect:
  1. **Never publish test messages to the shared `agent.tasks` topic
     exchange.** It is V1's route; a valid message-v1 payload published
     there will start a *real V1 workflow* (V2 observed exactly this race
     live before switching to queue-direct publishing). Submit through the
     V2 gateway (`:8083`), or publish directly to the `ea-tasks` queue
     (the D-routing design) as the m0 gate's own harness does.
  2. **V1's queues and dashboards are live production for its own record.**
     Verify V1's health as a *side condition* of every V2 check — its
     staying green throughout your evaluation is itself a claim you are
     reproducing (the coexistence claim, findings §4.1).

**If your evaluation environment shares a network with anything you cannot
risk exposing, stop and isolate it first.**

## Prerequisites

1. A running V2 deployment (Chapter 14, or the `deploy-v2/mN` install
   scripts), with SSH access as `<user>` to the three VMs. Check that the
   deployment was recently rebooted — if so, bring the stack up in
   dependency order first (Chapter 14 §14.5); everything is
   `restart: unless-stopped`, so mostly you are just confirming.
2. The agent catalog (`agent-roster`) reachable, with the capability you
   will request genuinely present in its index — the manager routes by
   exact match against real catalog references; an invented capability is
   rejected at publish (ledger entry 12 made that a feature).
3. The report contract, restated (from `deploy-v2/m5/report-contract.md`):

| Field | Meaning |
|---|---|
| `title` | short human label for the task |
| `agent_capability` | the capability the manager matches against the catalog |
| `task_brief` | the actual instruction given to the ephemeral executor |

## The gate-by-gate checklists

Each milestone's signed test procedure (TP-M0 … TP-M5) is the *record*;
what follows are the *live commands* that let you re-derive its verdict
yourself. Evidence packs for every row live in `deploy-v2/mN/evidence/`.

### M0 — chassis (broker topology, engine, network)

| Check | Command | Expect |
|---|---|---|
| Queue declared once, with its argument | `ssh <user>@<execution-host> 'docker exec <broker-container> rabbitmqctl list_queues name durable arguments'` | `ea-tasks` durable with `x-max-priority: 3`; `ea-tasks.dlq` present. (RabbitMQ cannot add the argument later — that is why it lives here.) |
| Netplan parses for real | `ssh <user>@<role-host> 'cat /etc/netplan/*.yaml'` then `sudo netplan apply` | byte-level: a `network:` root key present (ledger entry 1's rule); apply exits clean |
| Network matrix | re-run the m0 install's network-verification stage | all L3 pairs OK; outbound reach; AMQP + temporal ports open on the execution VM |
| Engine on the shared network, compose-declared | `ssh <user>@<execution-host> 'docker inspect <temporal-container> --format "{{json .NetworkSettings.Networks}}"'` | the shared network only, alias declared — no manual attaches (ledger 2) |
| Cross-VM publish proof | the m0 gate's publish test (from the front VM over AMQP) | message lands in `ea-tasks`, fetched + acked with the original payload |

**V1 side-condition:** V1's own queues still show their consumers; the
broker serves both organizations.

### M1 — the message bridge

| Check | Command | Expect |
|---|---|---|
| Consumer present | `rabbitmqctl list_queues name messages consumers` (as above) | `ea-tasks`: exactly 1 consumer (the V2 bridge), 0 messages at rest |
| Throughput + idempotency (T1/T2) | publish via `deploy-v2/m1/tests/` harness: 50 messages, then 50 duplicate task_ids | 50 started, then **+0** |
| Crash tolerance (T3) | `kill -9` the bridge container, publish 20 | all 20 started after restart, no doubles |
| Poison routing (T4) | publish 3 invalid messages | 3 land in `ea-tasks.dlq` with the rejection reason as a header (`deploy-v2/m1/evidence/m1-dlq-sample.json` shows the shape); consumer stays up |
| Engine restart (T5) | restart the temporal stack mid-run | the 5 in-flight messages still start their workflows |

### M2 — the durable core (lifecycle + worker)

| Check | Command | Expect |
|---|---|---|
| Clean path | `bash deploy-v2/m2/tests/run-task.sh` (one trivial task) | report `success`; executor container reaped |
| Failure / timeout / crash paths | the m2 harness's injected variants (exit-1; hang past TTL; kill mid-activity) | each surfaced with its reason; the crash case is reaped by the **independent reaper**, and the workflow retries to a clean final state |
| Mixed runs, zero survivors | `bash deploy-v2/m2/tests/mixed-runs.sh` | 10/10 pass; afterward `ssh <user>@<execution-host> 'docker ps --filter name=ea- --format "{{.Names}}"'` shows only the persistent services (bridge, lifecycle, worker, engine, broker) — **no per-task executor containers** |
| No-pull rule (TC-M2-06) | delete the pinned worker image, restart the lifecycle | the lifecycle **refuses to serve** (`no-pull deploy gate FAILED: pinned image absent`); restore the image → serving again. Zero pulls in the logs |
| Per-task logs | `ssh <user>@<execution-host> 'ls /var/ea/tasks/'` | one `<task_id>.log` per task |

### M3 — executors + credentials

| Check | Command | Expect |
|---|---|---|
| Boot time, 3× | `bash deploy-v2/m3/tests/boot-time.sh` | p50 ≈ 1.4 s; reproducibility within the recorded Δ (evidence: `boot-time-table.txt`) |
| Persona correctness | read the executor's boot self-report | sources match the catalog (`agent_repo`, llm-wiki, hindsight), persona matches the roster entry |
| Failure paths | the harness's failing briefs | exit code 2 and a failure-shaped self-report, twice, plus the control |
| Real coder work | one approved repo task | a real commit on a `task/<task_id>` branch of the demo repo (the acceptance commit `7c9a32c` is the record) |
| Token lifecycle | run `deploy-v2/m3/issue-token.sh`; call the catalog API with the token; revoke; call again after 5 s | 200 → (revoke) → **401**. Both halves of the check read the same variable; the 5 s sleep is the propagation margin (ledger 13) |
| Secret hygiene | `trivy image --scanners secret ea/hermes-ephemeral:1.0.0` (and every other deployed image) | 0 secret findings; lang-pkg findings inside pinned runtimes are accepted residuals, per-image |

### M4 — memory

| Check | Command | Expect |
|---|---|---|
| Read/write from a spawned executor | the G1 readback test | write persists; read-back equals the written body |
| Cross-task recall (G2) | fetch with a *different* task_id | the earlier task's learning is returned — scope rule holds |
| llm-wiki hydration (G3) | shallow-clone the wiki repo from an executor context | clone + README readable |
| Catalog regression (G4) | re-run the boot-time harness with sources live | self-report still shows all three sources true |
| Hydration latency (G5) | the 3-run latency table | totals ≈ 0.8–0.9 s against a 600 s TTL — ~99.8% headroom |
| Data isolation (G6) | `ssh <user>@<memory-host> 'docker volume ls'` | `ea-hindsight_ea-hindsight-pg-data` — distinct engine, host, and volume from V1's store; V1 rows absent from V2 reads (the seeded-entry proof) |
| Curation loop | push a new standard doc + CHANGELOG entry to the wiki repo; clone fresh | new doc found alongside the old ones (D-curation: humans curate; agents never write to it) |

**Honesty note:** no embedding provider is staged — the zero-vector
fallback runs (`EMBEDDINGS=none`, D-embed). Reads are q-driven and
functional; semantic ranking is *not* part of what M4 demonstrates.

### M5 — the front door and the whole system

| Check | Command | Expect |
|---|---|---|
| Gateway health | `curl http://<front-host>:8083/healthz` | 200. (V1's gateway stays on `:8080` — check it too; both must answer.) |
| Executor default asserted | `ssh <user>@<front-host> 'docker inspect ea-m2-lifecycle-1 --format "{{json .Config.Env}}"'` on the execution VM's compose | `EA_EXECUTOR_DEFAULT=hermes` — applied by the m5 §2' stage, idempotently, on every invocation |
| Submit | `curl -s -X POST http://<front-host>:8083/ -H 'Content-Type: application/json' -d '{"title":"Evaluator smoke test","agent_capability":"<real catalog ref>","task_brief":"Create hello.txt containing hello."}'` | immediate `{"task_id":"<uuid>","status":"accepted"}` — the gateway holds no state and no credentials |
| Watch the workflow | Temporal UI (below), locate `TaskWorkflow` for your task_id | exactly one workflow; event history: started → activity → completed |
| Poll the report | `curl -s http://<front-host>:8083/gateway/reports/<task_id>` | `status: success` with an artifact pointer (`/var/ea/tasks/<task_id>.log`, or branch + commit for coder tasks) |
| Zero survivors | `docker ps --filter name=ea-` (as in M2) | no per-task executor containers remain |
| Failure injections (F1–F5) | with operator help, per the m5 §5 runbook | F1/F2: an nft **forward-hook** block (container egress, not host `output`) produces failure-shaped reports; F3 (kill PID 1) and F4 (TTL expiry) are absorbed by the M2 retry policy — recover-and-complete, zero survivors, *policy-graded CHECK with the policy recorded*; F5: report written after a manager restart |
| Hardening | re-run m5 §6: trivy sweep, env sweep, token lifecycle | 9/9 images clean; no owner-long-lived token in any container env; 200 → 401 |

## Dashboards — watch the machinery yourself

The gateway report tells you what the system *says* happened. The two
dashboards let you watch what *actually* happened.

**Temporal web UI — the workflow view.** Open
`http://<execution-host>:8080`. It serves both organizations — a small
coexistence lesson in itself, since V2 reuses the engine deliberately.
Locate the `TaskWorkflow` whose ID is your task_id: exactly one per
accepted request; read the input (the task message) and the result (the
executor's outcome). On a failed task the history shows the retry chain
and the failing event.

**Broker management — the queue view.** Reach it the way the estate's
binding decision allows (ask the operator; the binding is recorded in the
m0 decision log — a loopback-only design later opened by owner decision is
a regression to *report*, not to exploit). Watch:

1. **Queues → `ea-tasks`:** your message lands (0→1) and drains (1→0).
   Exactly one consumer while healthy. Beside it, V1's
   `agent.tasks.durable` with *its* consumer — both queues served by the
   one broker, never crossing.
2. **`ea-tasks.dlq`:** after the T4/TC-M1-01-style poison test, the
   rejected messages with their rejection-reason headers.
3. **Exchanges:** `agent.tasks` carries V1's routing only; V2 publishes
   queue-direct (D-routing) — if you see a V2 bridge bound to the topic
   exchange, that is a regression against the coexistence decision
   (ledger entry 10's context).

<!-- DIAGRAM: two-organizations-one-estate (owner-drawn) -->

*The diagram above is the coexistence picture these dashboards show: one
estate, two organizations, shared VMs and broker, disjoint queues, volumes,
and ports. It anchors Chapter 11; this chapter cites it because the
dashboards are how you verify it.*

### The live evaluation checklist

Run these in order while one request executes:

| When | Where | What you see | Which claim it verifies |
|---|---|---|---|
| t=0 | gateway `:8083` | instant `{task_id, status: accepted}` | stateless, credential-free front door |
| t≈1 s | broker | message lands in `ea-tasks`, drains | queue-direct publish (D-routing); the manager validated before publish |
| t≈2 s | Temporal UI | one `TaskWorkflow` for the task_id | durable engine; exactly one workflow per request |
| t≈3–4 s | execution VM | executor container up; ~1.4 s boot, three files hydrated | ephemeral execution; the asserted executor (not the stub) |
| during | demo repo (coder tasks) | commit lands on `task/<task_id>` | credentialed write-back, per-run token |
| at end | execution VM | executor container gone; queue empty; **V1's dashboards still 200** | zero survivors **and** coexistence untouched |
| at end | gateway | report `status: success` with artifact pointer | the human report loop — the only access an engineer needs |

## Claim-by-claim verification (against the findings report)

Each headline claim of `version 2/V2-findings-report.md`, and how you
confirm it hands-on:

| Claim (findings §) | Verify by |
|---|---|
| Coexistence is the cheapest isolation — two live organizations, one estate (§4.1) | The dashboard views above: both queues served by one broker, `ea-*` and V1 containers coexisting; the takeover incident (ledger 8) repaired by one compose `name:` — read `deploy-v2/m4/evidence/isolation-check.txt` |
| The gate rule caught every major error before it shipped (§4.2) | For each of the 13 ledger entries, read its discovery vector in Chapter 12 — gate, review, or byte-level check; confirm the fix commits exist in the repo history |
| Stage gates re-assert skipped preconditions (§4.3) | Re-run the m5 install with the stage-gate env set: §2' re-applies and asserts the executor default on every invocation, hard-failing otherwise |
| Display masking is a debugging hazard (§4.4) | Byte-read a tracked compose (`grep -n RABBITMQ_URL deploy-v2/m1/compose.yaml`): interpolation only, no literal — never trust terminal-masked display |
| Executor-vs-stub is observable and assertable (§4.5) | The `docker inspect` env check above; and TC-M5-02(c): the coder flip through the identical gateway→manager→queue path, restored after |
| Publishing is queue-direct (§3.2) | `EA_TASKS_QUEUE=ea-tasks` in the deployed compose; no `TASKS_EXCHANGE`; default exchange, routing key = queue name |
| Timeline 2026-11-13 → 15, six signed TPs (§1, §2) | The signed tables in `deploy-v2/mN/evidence/tp-mN-results.md` (TP-M1 … TP-M5) and the m0 install log |
| What remains (§5) | Chapter 13's deferred list — including the two dependency refreshes whose residuals the trivy sweep records per-image |

## The front door: today and next

**Today:** the structured HTTP POST on `:8083` is the wired entry point —
the same shape V1 proved, ea-named, with the manager validating every
request before publish.

**Next:** the Chief-of-Staff milestone (TP-V2-M1) places a persistent
resident agent between the desktop and this gateway — approval flow,
two-tier work board, priority field. Every command in this chapter is the
manual equivalent of what the CoS will do; the machinery being evaluated
is the machinery it will submit into, unchanged.

---

*All host references in this chapter are placeholders by convention.
Concrete addresses, ports, and credentials live with the operator in the
gitignored env files and are never printed in this book.*
