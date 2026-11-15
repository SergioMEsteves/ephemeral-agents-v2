# Chapter 4 — The Work Order

> **V2 pointer.** The thesis-level treatment of the work order — the
> self-sufficient envelope, the field-by-field tour of message-v1, and the
> "complete or rejected" discipline — lives in the V1 book
> (`book/ch4-the-work-order.md`) and is unchanged in principle. This chapter
> covers what the V2 build *did to* the work order: how the contract may
> evolve, the fields it grew, and where it travels.

> **In plain terms.** Every piece of work still travels as a small, verifiable
> ticket. V2 changed three things about the ticket, and only three: it wrote
> down the rule for how the ticket may *change*, it added a priority field the
> requester can declare, and it changed the door the ticket goes through —
> from a shared letterbox that two companies were checking, to V2's own slot.
> It also added a wax seal — not to stop tampering, but to prove afterward
> whether anything was tampered with.

## 4.1 What V2 does not change

The V1 order's core properties carry forward untouched. `task_id` is still
the single name of the work — and now explicitly *the idempotency key*: the
Temporal workflow ID is `task_id`, so a duplicate task_id is absorbed, never
a second workflow (proved signed at the M1 gate's duplicate case,
TC-M1-03, and used deliberately by the M1 design's ambiguous-submit retry
rule). The
envelope is still self-sufficient; the registrar's composition rule, the
strict schema with `additionalProperties: false`, and the deadline-carried
`ttl_s` all stand. The V2 acceptance request — *add a health endpoint* —
traveled through the V2 pipeline as an ordinary message-v1 order, and its
commit (`7c9a32c` on the task branch) was produced by exactly the V1-shaped
contract, plus the two fields this chapter describes.

## 4.2 The evolution rule: additive-only, with teeth

V2's first formal decision about the work order was not about any field — it
was about the *schema's future*. The policy (platform design §5): **message-v1
stays the contract; changes are additive only** — new optional fields with
safe defaults. A breaking change triggers a proper message-v2, with a version
field in the header and a documented transition. No ad-hoc edits to meaning.

The 2026-11-10 design review then forced the policy to be written with teeth,
because the policy as first worded and the schema as seeded were
contradictory. The seeded schema is strict — `additionalProperties: false` —
so the draft wording "consumers tolerate unknown fields" was simply false.
The corrected mechanics are:

1. An additive field is added to `schemas/message-v1.json` itself, as an
   optional property with a documented default (absent = default behavior).
2. Validators are updated **in the same gated change as the consumer-side
   support** — a field and its consumer land together, because consumers
   validate against the current schema and would otherwise reject the new
   field they are supposed to serve.
3. The schema's own metadata is corrected at the same first touch (the
   V1-era "POC task message" title was retired in the de-POC sweep).

The first field to travel this path was not new knowledge — it was the
review's first exercise of the rule: `priority` and `approval_hash` entered
the schema additively, each in the same gated change as its manager-side
consumer (pre-build gap-closure commit `f451791`; the schema carries both
fields with their defaults documented in place).

## 4.3 The first additive field: `priority`

The V1 book's rejected-decisions list included "no field for priority" by
omission — V1 simply had no mechanism for ordering work. V2's
chief-of-staff milestone made ordering a first-class need, and the decision
(D8) keeps the chapter's founding rule intact: **the requester declares
priority *inside* the work package; the manager validates and applies it;
the broker enforces pickup order.** The declarer never touches the broker —
"the agent proposes, the code disposes."

Three sub-decisions, each recorded:

- **The encoding is coarse** (OQ1, closed 2026-11-10): an enum —
  `high` / `normal` / `low`. Rationale: the declarer is an LLM; a 1–10 scale
  would carry precision the judgment source does not have. Three levels
  survive judgment, make declare-everything-high visible (the declared value
  is logged at the manager, never coerced), and map cleanly onto the
  broker's `x-max-priority`. Fine-grained ordering stays where it belongs —
  in submission order and the CoS's own backlog.
- **The field lands with M1** (OQ4, closed 2026-11-10): field and consumer
  in the same gated change per the §5 rule, and the queue's
  `x-max-priority` argument declared exactly once, under the final `ea-*`
  name (Chapter 5). The former reason to defer — keeping the first test
  run small — had already been superseded by the build-start security
  items, so deferral had no remaining advantage.
- **Out-of-range is rejected, not clamped.** The manager's validation
  (`services/manager/m1.go`) rejects anything outside the enum, and the
  contract test suite asserts both directions (`priority-enum-accepted`,
  `priority-out-of-enum-rejected` — 14/14 green at `f451791`). The signed
  end-to-end assertion — a higher-priority package picked up ahead of a
  lower one — belongs to TP-V2-M1 (assertions 2–3), the pending CoS gate.

## 4.4 The publish path: queue-direct (D-routing)

V1's work order traveled over a *topic exchange* — published with the
agent's capability as the routing key, so any interested component could
subscribe without the publisher knowing it existed. That indirection, pure
gain inside one organization, became a liability the moment two
organizations shared one estate.

**The race, observed live.** Both V1's bridge and V2's bridge bind
`agent.tasks.#` on the *shared* exchange, and both derive the same Temporal
WorkflowId from `task_id`. First-start wins. In the first M5 end-to-end run,
two V2 acceptance tasks were exchange-routed and V1's bridge won the race —
the tasks were executed on V1's pipeline, artifacts written under V1's tree
(`bb41c4cd`, `cceeb912`). Nothing errored; the work simply happened in the
wrong company. The M5 smoke test had passed earlier for exactly this reason:
it published straight to the `ea-tasks` queue and never touched the exchange.

**The fix: publish to the queue, not the exchange.** The V2 manager now
publishes *directly to the `ea-tasks` queue via the default exchange*
(routing key = queue name; `EA_TASKS_QUEUE=ea-tasks`, the exchange
declaration skipped when unset). This removes the race at the publish point:
a message addressed to a queue has no routing for V1's bridge to intercept,
and V1's own publishes to the shared exchange continue to serve V1
undisturbed (commits `28b8616` for the publish path, `a710d08` for the
compose wiring; the decision is recorded as D-routing in the build's
decision log).

**The failure the fix itself had to survive** is ledger entry 10: with the
exchange unset, the manager's first version still published with the
capability string as the routing key — against the default exchange, that
silently unroutes, and messages vanish with no error. The rule: *publish-mode
constants (exchange, routing key) change together and carry a test that
asserts the effective routing target.* (The companion defect — the fix's
first commit claiming code that a gitignore pattern had silently excluded —
is ledger entry 9, told in Chapter 12.)

**The trade-off, stated.** Capability-based topic routing — publish by what
the work *needs* rather than where it *goes* — is not exercised on the V2
path; the queue is the subscription point. If fan-out by capability returns,
it returns as a versioned message-v1 additive change, through the §4.2 rule
— the same door `priority` came in through.

## 4.5 The approval hash: tamper-evidence, not tamper-prevention

The second additive field is `approval_hash` — SHA-256 over the UTF-8 bytes
of the `behavioral_spec`, **whitespace-exact** (no trimming, no
normalization, no JSON re-encoding — byte-for-byte what the approval
covered; the canonicalization is fixed in code, not configurable). It rides
the same rules as `priority`: additive-optional, landed with its consumer.

At the M1 gate the manager enforces exactly two checks, through a per-task
hash ledger:

- **Retry integrity.** The same `task_id` must carry an identical spec hash
  across its ambiguous-submit retries (the M1 design's failure-behavior
  section: an uncertain gateway outcome is retried with the same task_id).
  A different
  hash on a retry means the payload was swapped between attempts — reject
  and surface to the owner. A payload that changes *shape* between attempts
  (hash present, then absent) is the same violation.
- **Mismatch-reject-and-surface.** A declared hash that does not match the
  recomputed one is rejected and reported, never silently accepted.

And then the honest limit, stated in the same sentence that defines the
control: **because the requester supplies both the spec and its hash, the
hash cannot prove the spec matches what the owner approved.** It is
tamper-*evidence* for post-hoc audit, not tamper-*prevention*. The control
that actually stops an unapproved submission is the ask-before-submit
approval loop itself — recorded as the accepted residual of rung A. The
enforcement upgrade is known and queued: the gateway records the hash at
the moment the owner approves, making the pin owner-sourced — a later,
separately-gated change, since the gateway is untouched by M1. The gate's
mismatch test injects on the manager side (replayed payload vs. recorded
retry hash), not on the board side.

The V1 chapter's rule survives translation: the gate must assert the
outcome, not the absence of debris. A hash that *cannot* prevent tampering
but *must* expose it is the same discipline pointed at a different failure.

## 4.6 Design decisions and rejected alternatives (V2 delta)

**Decision: additive-only evolution with field+consumer landing together.**
Alternative: free-form tolerance (consumers ignore unknown fields) —
rejected because the seeded strict schema already forbids it, and
correctly: silent tolerance is how drift stops being loud. Alternative:
immediate message-v2 — rejected; nothing yet requires a breaking change,
and a version bump is a cost, not a ceremony.

**Decision: queue-direct publishing.** Alternatives: keep exchange routing
with a V2-only routing-key namespace (leaves both bridges racing on the
shared exchange for any key both match — the observed failure mode), or a
separate V2 exchange (recreates V1's topology beside V1 for one
publisher's benefit, and still exercises no capability fan-out). Rejected
in favor of the smallest change that removes the race at the publish
point, with the trade-off recorded rather than hidden.

**Decision: a hash ledger at the manager, not end-to-end signing.**
Alternatives: owner-signed approvals at M1 (rejected: it moves the gateway
— the one component M1 deliberately does not touch), or no integrity check
until the gateway upgrade lands (rejected: retries were already a live
code path, and retry integrity needs no new component).

## 4.7 The rule this chapter teaches

V1 taught: *the order is complete, or it is rejected.* V2 adds two clauses
learned on the same estate: **the contract evolves only through the gate
that builds its consumer** — a field without its consumer, or a consumer
without its field, is an incomplete change and is refused the way an
incomplete order is; and **address the destination, not the medium** — when
two systems can hear the same broadcast, the fix is not a better broadcast,
it is a direct line.
