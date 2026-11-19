# Chapter 5 — The Durable Core

> **What this chapter adds.** The thesis-level treatment of the durable core — the
> workflow engine, the two clocks, the reaper, and the zero-survivors
> guarantee — is stated in full here and is unchanged in principle. This chapter covers the V2 delta: the durable core
> rebuilt under a second name, on one estate, *beside* the first one.

> **In plain terms.** The mill that executes tickets — pick up, keep safe,
> spawn, watch, clean up, report — is the same mill the first build constructed. This build rebuilt it
> with new names so it could run next to the original without either
> interfering, and in the rebuilding the V2 build learned the three rules
> this chapter is about: network membership is declared in the blueprint,
> never attached by hand; a queue's shape is written down in exactly one
> place; and a queue family — work, dead-letter, response — is declared
> once, all together, before anything consumes it.

## 5.1 What V2 inherits whole

Every structural decision of the first build's core carries forward: work lives in a
durable workflow instance keyed by `task_id`, not in a process; the
sequence *dispatch → spawn → poll → reap → report* is one inspectable
record; the two clocks (wall-clock `ttl_s` carried by the order, reasoning
clock `max_turns`) end the same way; the reaper's zero-survivors check
remains a first-class failure condition. V2 did not redesign this — it
*re-proved* it, gate by gate, under the `ea-` names: TP-M1 6/6 (the bridge
path: throughput, duplicate idempotency, kill-9 redelivery, poison-pill
routing, engine restart recovery) and TP-M2 7/7 (the lifecycle path:
timeout, crash recovery by an independent reaper, ten mixed runs ending in
zero survivors). Evidence: `deploy-v2/m1/evidence/`, `deploy-v2/m2/evidence/`.

## 5.2 `ea-net`: membership is compose-declared

The first build's shared network carried a lesson the V2 build then paid for once more
— in ledger entry 2, and at higher stakes, because this time the breakage
took the *first* path down, not the second.

After the m0 apply, components could not resolve the engine service by
name: embedded DNS returned SERVFAIL, and the estate's first-build path was down
while every container showed `Up`. The root cause was two independent bugs
in the same class:

1. The first build had wired the shared network with a manual `docker network connect` —
   an attachment that every compose recreation silently drops. A network
   attached by hand is a network attached *once*.
2. A container attached to *two* networks with the same alias on both makes
   Docker's embedded DNS fail peer lookups outright — so the fix could not
   simply be "add the network next to the default one"; the services had to
   live on the shared network *only*.

The rule, now standing: **shared-network membership is compose-declared,
never attached by hand.** The pattern — services live only on `ea-net`,
aliases = service names, network declared `external` in every compose —
was already followed by the broker's compose and became the template for
every multi-service V2 stack. The committed form is one paragraph of
compose (`deploy-v2/m0/rabbitmq/compose.yaml`):

```yaml
networks:
  ea-net:
    external: true
# (per-service:) networks: { ea-net: { aliases: [rabbitmq] } }
```

The deeper point is the one made about load-bearing state in the first book: if a
property matters to correctness, it must live in the artifact that survives
recreation — not in a session's worth of hand-typed commands.

## 5.3 The queue family, declared once

The first build's core had one queue and its dead-letter sibling. V2 declares a
three-member family, in one place, in the M0 milestone (commit `1f98b82`,
broker section of `deploy-v2/m0/install.sh`):

| Queue | Shape | Role |
|---|---|---|
| `ea-tasks` | durable, `x-max-priority: 3` | the work queue — the subscription point for V2's bridge |
| `ea-tasks.dlq` | durable | holds rejected ("poison") messages, each carrying its rejection reason |
| `ea-tasks.response` | durable | the report path — the manager consumes it, filters by its own `task_id`s, and writes each report |

The family is declared through the broker's management API by the install
script, guarded idempotently (the declare step runs only when the queue is
absent), with the broker password staged through a stdin-fed config file
never argv. The first-build-era topic exchange keeps its name and stays shared —
`ea-tasks` even carries a topic binding on it from this declaration — but
V2's manager addresses the queue directly (Chapter 4, §4.4). Coexistence
property, verified live at M1: the first organization's `agent.tasks.durable` / `agent.tasks.dlq`
and V2's `ea-tasks` / `ea-tasks.dlq` are *distinct consumers on the same
broker*, each draining only its own family.

The single-declaration discipline has a design-history hook worth keeping:
the `x-max-priority` argument could only be set when the queue was created,
and queues do not survive renames — so the priority-capable declaration was
deliberately scheduled into the rename's queue re-creation, **exactly once,
under the final `ea-*` name** (the OQ4 closure, 2026-11-10). Declare once,
under the final name, or be forced to choose between dropping the
capability and racing every consumer's re-declare.

## 5.4 The declaration point is load-bearing

Ledger entry 6 proved the single-declaration rule is not bookkeeping — it
is correctness. The M1 gate failed at its first case: zero messages
consumed, with the V2 bridge logging
`PRECONDITION_FAILED: inequivalent arg 'x-max-priority'`. The bridge's own
queue-declare had omitted the priority argument; the broker rejects an
inequivalent re-declare of an existing queue — and should. That refusal is
what keeps two components from silently agreeing on *different* queues that
share one name.

The rule now in force: **every queue-declare site must byte-match the
canonical declaration (`x-max-priority: 3` on the `ea-*` task queues), and
a queue-shape constant lives in one place per service.** The failure mode
it closes is exactly the drift class the first book catalogued: two writers, one
implied contract, no one owning the shape.

## 5.5 What the gates proved about the family

The three-member shape earned its keep in signed evidence (TP-M1, all six
cases PASS; `deploy-v2/m1/evidence/`):

- **Poison has an address.** A message that permanently fails consumption
  is dead-lettered to `ea-tasks.dlq` with its rejection reason attached as
  a message property — the DLQ sample is part of the evidence pack.
- **Duplicates are absorbed.** A re-published task_id added zero workflows
  (idempotency on the single name, Chapter 4).
- **The queue absorbs the bridge's death.** Kill the consumer mid-run:
  unacknowledged messages redeliver, no doubles. Stop the bridge entirely
  and publish: the durable queue holds the messages until restart, then
  drains to zero and starts the workflows (TC-M1-06, the strongest variant).
- **The engine restarts out from under it.** A full engine restart
  mid-consumption recovers without loss.
- **The response leg is self-healing by default.** The manager's response
  consumer treats any channel or connection error as a retry-after-backoff
  event — reconnection is the default, not a fatal path.

## 5.6 Design decisions and alternatives (V2 delta)

**Decision: same broker, new queue family.** Alternative: a separate broker
for V2 — rejected: the estate runs one of everything deliberately, and two
brokers would double the operational surface to prove nothing new. The
queue family is the isolation boundary that matters; the broker is shared
infrastructure, like the network.

**Decision: compose-declared membership, aliases = service names.**
Alternative: hand-attachment at install time (the first build's habit) — rejected by
ledger entry 2: it does not survive recreation, and its failure mode is
silent (`Up` everywhere, name resolution dead).

**Decision: one canonical queue declaration, byte-matched everywhere.**
Alternative: per-consumer declarations derived from configuration —
rejected by ledger entry 6: derivation is where inequivalence is born.

**Decision: single workflow engine, honest about the trade.** Carried
forward unchanged from the first build (and stated in the first book); this build neither
challenged nor relieved it — distribution remains deferred until scale
demands it.

## 5.7 What this buys

The durable core is the reason everything else stays simple, and V2 adds a
second payoff: because the core's boundaries are all *named* — one network,
one queue family, one engine — two copies of the whole core can coexist on
one estate with no shared mutable state. The first build's stacks were verifiable
mid-build throughout the V2 build (its queues drained by its own bridge,
its dashboards answering), and no route of this build ever touched a first-build queue. The
organization-scale claim — N systems per estate — got its first real data
point here, and the data point is boring, which is the highest compliment
infrastructure can earn. The coexistence rules themselves (compose project
names, volumes, ports) are Chapter 11's subject.
