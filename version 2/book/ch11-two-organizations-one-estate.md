# Chapter 11 — Two Organizations, One Estate

> **In plain terms.** For the entire V2 build, V2 was never the only thing
> running on the machines. V1 — frozen as a record, still live as a system
> — kept serving on the same four virtual machines, behind its own front
> door, from its own queues, the whole time. This chapter is the rulebook
> that made that possible, the one race the rulebook could not prevent and
> the fix that removed it, the one time the rules were violated and what
> the restoration looked like, and the running proof: at every point of
> the build, V1 could be checked and was healthy.

## 11.1 The constraint that shaped the build

The estate is version-agnostic hardware; organizations live on it by
naming, not by welds. V2's build therefore faced a constraint V1 never
had: build a second, complete organization *beside* the first, on shared
machines, without ever taking the first one down or dirtying it.

There were three reasons to accept that constraint rather than route
around it:

- **V1 is the evidence baseline.** Its book, its signed gates, and its
  deploy tree are cited by hash; silently renaming or rebuilding its
  estate would break traceability to every claim V1's record makes.
- **V1 is the fallback.** A build that destroys the working system it is
  replacing has no rollback. Coexistence *is* the rollback plan.
- **V1 is the control group.** A frozen, healthy, fully observable
  organization on the same hardware is the perfect detector for V2
  defects: anything V2 did to V1 would show up in V1's own health.

One owner decision made the shared parts safe before the first milestone:
**preserve V1's credentials through the coexistence period.** V2's broker
user is a fresh `ea:` principal on the *shared* broker, and V1's broker
password was reused; the Temporal database user was aligned to V2's fresh
password via socket-authentication (`ALTER USER`) rather than minting a
new one against a data volume that still held the old credential — the
volume side is authoritative when old, the env file when new (ledger
entry 3). Two organizations, one broker, deliberately: the isolation that
matters is at the queues and the routes, not at the wire protocol.

<!-- DIAGRAM: two-organizations-one-estate (owner-drawn) -->

## 11.2 The rule set: born ea-named

The `ea-` rename was executed as a gated micro-gate *before* the build
began, not as cleanup after it. That ordering is the chapter's first
lesson: front-loading the coexistence rules into a committed mapping
table turned them into a checklist that then held for five milestones —
with exactly one exception, caught by the ledger (entry 8), which Section
11.4 tells. The rule set, axis by axis:

| Axis | V1 (untouched) | V2 (born this way) |
|---|---|---|
| Compose project | `m1`, `m2`, `m5`, `hindsight` | `ea-m1`… `ea-m5`, `ea-hindsight` |
| Containers | `m1-topic-bridge-1`, … | `ea-m1-topic-bridge-1`, … |
| Data volumes | `hindsight-pg-data`, … | `ea-hindsight-pg-data` (fresh) |
| Host ports | gateway 8080, memory 8081 | gateway 8083, manager 8086, memory 8082 |
| Queues | `agent.tasks`, `agent.tasks.durable`, `.dlq`, `.response` | `ea-tasks`, `ea-tasks.dlq`, `ea-tasks.response` |
| Docker network | `poc-net` | `ea-net` (compose-declared) |
| Images | `poc/*` | `ea/*` (digest-identical re-tags) |
| Env vars | `POC_*` | `EA_*` |
| Deploy root | `/opt/poc` | `/opt/ea` |
| Container labels | `poc.task`, `poc.owner`, `poc.expires` | `ea.task`, `ea.owner`, `ea.expires` |
| Demo repo | `ephemeral-poc-demo` | `ephemeral-v2-demo` |
| Broker user | V1's principal | `ea:` (scoped to the `ea-*` queues) |

Three rules carry the weight; everything else in the table follows from
them:

1. **Nothing inherits.** Every V2 compose file sets `name: ea-*`, `ea-*`
   container names, and its own volume. This is the rule whose violation
   is this chapter's one incident — and the reason it gets stated as a
   rule and not a preference.
2. **Distinct ports at the host; identical internals.** V2's gateway still
   listens on 8080 *inside its container*, exactly like V1's; coexistence
   moved the published host port (8083) and nothing else. The same
   pattern put V2's memory service on 8082 while V1's kept 8081 — one
   port number, zero code change.
3. **Distinct queues on the shared broker.** V1's `agent.tasks.*` family
   was declared once in V1 and was never touched again; V2's `ea-tasks`
   family was declared exactly once, under its final name, durable and
   with `x-max-priority: 3` — the single declaration point for the
   priority shelf Chapter 10 described. V1's queues remain in place
   pending the (later, deliberate) estate switch-over.

Two clarifications the record insists on. First, the shared
infrastructure — the broker and the workflow engine — is *deliberately*
shared: the m0 install reuses the live V1 broker and Temporal containers
when present, rather than standing up duplicates. Second, the registry
honesty: only three V1 images were ever registry-resident, and those
three were re-tagged `ea/*` with **digest-identical** verification — the
build's proof that the rename was naming, not code. The other six images
listed in the original rename plan had never been pushed at all (V1 built
them at install time); there was nothing to re-tag, and the correction is
recorded in the mapping itself.

<!-- DIAGRAM: build-order-and-estate (owner-drawn) -->

## 11.3 The race the rules could not prevent

Every axis in the table separates the two organizations except one they
share on purpose: the broker. And on that broker, one object was still
common property — the `agent.tasks` **topic exchange**.

V1's bridge binds `agent.tasks.#` and delivers to `agent.tasks.durable`.
V2's bridge — re-tagged, `ea-`-named, otherwise entirely its own system —
also bound `agent.tasks.#`, delivering to `ea-tasks`. Both bridges derive
the same workflow identity from the same field in the same message
format. When a task is published through the shared exchange, **first
start wins**: whichever bridge started first holds the route, and the
other organization's task goes to it.

This was observed live, at the first M5 end-to-end run. Two V2 acceptance
tasks were published exchange-routed, picked up by *V1's* bridge, and
executed on V1's queue — V1 did its job perfectly on work that was never
its own, and V2's tasks completed under V1's pipeline with artifacts in
V1's directory tree. Nothing crashed; nothing errored. The system routed
correctly by its own rules and produced the wrong org's result. That is
what makes coexistence bugs dangerous: every component is healthy.

Why the gates had not caught it: the earlier cross-VM publish test and
the smoke test both publish *directly* to the `ea-tasks` queue — which is
precisely the path the fix would use. The shared-exchange path was never
exercised until the full end-to-end ran. A test that bypasses the
integration point proves the components, not the integration.

**The fix (D-routing): queue-direct publishing.** V2's manager now
publishes directly to the `ea-tasks` queue — the default exchange, with
the queue name as the routing key, the exchange declaration skipped
entirely — so the shared topic exchange is no longer on the V2 task path
at all. V1's exchange route remains exactly as it was, serving V1's own
publishes. The race is removed at the publish point, without touching a
single V1 byte.

The fix earned two ledger entries of its own before it worked, both
instructive:

- The first "fixed" manager image did not contain the fix: the commit
  that claimed it was silently empty because ignore patterns intended
  for compiled binaries had masked the manager's entire source
  directory — `git status` showed a clean tree, and a clean tree is not
  evidence that sources are tracked (entry 9).
- The first working publish used the *agent capability* as the routing
  key against the default exchange — which silently unrouted; messages
  vanished with no error at all. Against the default exchange, the
  routing key must be the queue name; publish-mode constants must change
  together, with a test asserting the effective routing target (entry
  10).

After the rebuild and redeploy, the end-to-end ran green on the V2 path:
five hermes-executor acceptance runs COMPLETED with reports written and
zero survivors, and the coder-routed acceptance commit (`7c9a32c`)
produced through the identical gateway → manager → queue path.

**The trade-off, stated honestly.** Capability-based topic routing —
publish by routing key, subscribe by binding — is V1-only for now; the
V2 queue is the subscription point, not a topic. If fan-out by capability
returns, it returns as a versioned, additive message-v1 change. The
decision is recorded as **D-routing** in the deploy tree's decision log.

## 11.4 The incident: the day V2 took over V1's memory

The rule set held for m0 through m3. Then, at m4, it was violated —
briefly, completely, and instructively.

- **Symptom:** deploying the V2 memory stack replaced V1's containers and
  reused V1's data volume. V1's memory system went down, mid-build,
  without anyone intending to touch it.
- **Wrong assumption:** that compose project and volume names inherited
  from V1 were safe to carry over.
- **Root cause:** the m4 compose kept V1's project name (`hindsight`) and
  V1's volume name. To Docker Compose, a same-named project *is* the
  project — `up` against it replaces its containers and adopts its
  volumes. No error is possible, because nothing is wrong from the
  tool's point of view.
- **The fix** (commit `0209ffb`): the V2 compose became `name:
  ea-hindsight`, with `ea-hindsight-*` containers, a fresh volume of its
  own (`ea-hindsight-pg-data`, clean initdb), and its own host port
  (8082 while V1 kept 8081).

The restoration sequence — which is now part of the fix runbook, not an
afterthought — was executed in order: the takeover stack taken down; V1
brought back up from its own deploy tree (memory service healthy on
8081); V2 brought up as `ea-hindsight` (healthy on 8082). Both stacks
then coexisted with distinct volumes, exactly as the rule set demands.

Two things make this incident worth a section of its own. First, it
happened in the milestone whose compose file had been *most* heavily
edited — a caution against assuming that the most-transformed artifacts
are the most-checked ones. The inherited name looked *right* in every
diff review, because names that come from the source you are porting
from always look right. Second, it was the **only** violation of the rule
set across five milestones — which is the honest way to read the rule
set's quality: one miss, caught by its own symptom (V1's health), fixed
at the rule level, and never repeated.

## 11.5 The proof: V1 was verifiable all the way through

Coexistence is only a claim until the other organization is checkable
during the build. It was, at every stage:

- While V2's m1 gate ran its fifty-message load, its kill-9 redelivery
  test, its poison-pill injections, and its Temporal restart case, **V1's
  bridge stayed up, consuming `agent.tasks.durable`** — two bridges on
  two queue families, same broker, no interference.
- V1's dashboards answered `200` mid-build; V1's queues drained by V1's
  own bridge.
- **`agent.tasks.dlq` stayed at zero across the V2 gates** — no V1
  pollution from any V2 test. V2's own dead-letter queue held exactly
  its three m1 poison pills, which was the *correct* routing, and the m0
  gates drained both queue families to zero after their runs.
- After the m4 restoration, V1's memory service was healthy on 8081 with
  its original volume, and V2's on 8082 with a fresh one.
- Every milestone's evidence pack carries the same closing line, and the
  line is load-bearing: *V1 untouched throughout.*

This is the coexistence proof, and it supports the claim V2's thesis
added to V1's: that organizations of agents are **replicable** — N systems
per estate, not one system per estate. That claim got its first real data
point here, under adverse conditions the design did not get to choose:
two live organizations, one shared broker and workflow engine, an
overlapping build window, and zero downtime on the frozen side. The
finding is stated in the findings report without decoration: coexistence
is the cheapest isolation — one compose `name:` difference was, at the
worst moment, the entire difference between coexistence and takeover.

## 11.6 What coexistence bought, and what it costs

**Bought:**

- A permanent control group: every V2 gate ran with a healthy V1
  observable alongside, turning "V1 untouched" from a promise into a
  measured result at every milestone.
- Digest-identical re-tags proving the rename was naming, not code.
- V1's failure ledger exercised live as a rulebook: the compose-declared
  network lesson (entry 2) and the volume/env pairing lesson (entry 3)
  were both applied before they could recur, and the m4 incident (entry
  8) earned the rule set its sharpest clause.
- A clean switch-over story still ahead: V1's queues and stacks remain
  in place, healthy, and untouched, so the day V2 becomes the estate's
  only organization is a deliberate act with a proven fallback behind
  it — not a migration under pressure.

**Cost, named honestly:**

- Every name is typed twice, and the mapping table that keeps the two
  apart is now load-bearing documentation: the day it drifts from the
  composes is the day the next inheritance bug gets its chance.
- The shared exchange remains shared. Queue-direct publishing removed
  the race from V2's path; it did not make the exchange itself safe for
  two first-start-wins consumers. That repair, if wanted, is a versioned
  change — which is why the trade-off was accepted and recorded rather
  than silently carried.
- The credential-preservation decision couples the two organizations'
  secrets for the duration of the window — a deliberate, logged
  acceptance, revisited at switch-over.

Both front doors are open. Both organizations are healthy. The next
chapter turns to the failures this build accumulated anyway — because a
coexisting build fails in its own distinctive ways, and each one wrote a
rule.
