# Chapter 10 — The Front Door

> **In plain terms.** Everything behind the door — the work order, the
> durable core, the roster, the credentials, the memory — was rebuilt under
> the `ea-` names and re-proved gate by gate. This chapter is the door
> itself: the same two services as the first organization's door, standing on the same machine
> as the still-running first door, at a new address. It ends with the thing
> the first book promised at this exact point — the Chief of Staff — except that
> this build can report something the first build could not: the design is finished, specified
> down to individual gate assertions, and waiting for its build. Nothing in
> that design is running yet, and this chapter is careful never to pretend
> otherwise.

## 10.1 The boundary that matters

The single most important architectural boundary in the system is the one
between the **thinking layer** and the **execution layer**, and V2 did not
move it:

- **Thinking layer** — the human and their assistant (the Hermes Desktop,
  in the reference scenario). Free-form conversation: research,
  refinement, doubts, reformulations. Nothing here costs the pipeline
  anything, because nothing here is work yet.
- **Execution layer** — the pipeline. Structured work orders only. Durable,
  credentialed, audited, billed. Nothing here is ambiguous, because
  ambiguity cannot survive the strict schema (Chapter 4).

The V2 build is the strongest evidence yet that the boundary earns its
place. The whole staged build (M0 through M5) ran on an estate where the first organization was
still live and serving — and at no point did conversational traffic reach a
queue, or queue traffic reach a conversation. The front door's job is to
make the crossing *deliberate*, and across five milestones every crossing
was.

## 10.2 The two doors, rebuilt side by side

The front-of-house VM now hosts two front doors:

- **The first organization's door** — the original gateway, listening on the host at **8080**,
  still serving the first build's pipeline for as long as the coexistence window runs
  (Chapter 11).
- **V2's door** — `ea/gateway:1.0.0`, the same thin, stateless receptionist
  service, rebuilt under the `ea-` name, listening on the host at
  **8083**. Inside the container nothing changed at all: the service still
  listens on 8080, exactly as its first-build ancestor does. Coexistence moved one
  compose line — the published port — and no line of code.

Behind it sits **the registrar (the "manager")** — `ea/manager:1.0.0`,
reached by the gateway as `manager:8086` inside the V2 network. On each
request it does what Chapter 3 specified and the first build proved:

1. clones the roster and reads the machine index (Chapter 6);
2. matches the request's capability to a role — exact match first, then a
   deliberate, case-insensitive fallback;
3. composes the final work order: the role's behavioral specification plus
   the human's brief, merged into the self-sufficient message-v1 envelope
   (Chapter 4);
4. publishes it to the V2 work queue — `ea-tasks` — and from there the
   durable core takes over (Chapter 5);
5. later, correlates the result back from `ea-tasks.response` and turns it
   into a **human report** — status, artifact pointer, and, on failure, a
   reason a person can read. V2's reports land in a report directory of
   their own (`/opt/ea/reports`), beside — never inside — the first build's.

The report loop closes the circle, and the single-path rule still holds:
the human never talks to the durable engine, the queue, or the workers
directly — only to the gateway. One path in, one audited boundary, one
artifact trail back.

## 10.3 The running example, end to end

V2's acceptance request is one sentence: *"add a health endpoint to the
POC project."* Carried through the V2 front door, it went:

gateway (8083) → immediate acknowledgment with a task identifier →
manager validation → `ea-tasks` → ephemeral executor → task branch →
report.

The M5 gate ran this path five ways against the real hermes executor —
every run **COMPLETED**, every report written, **zero surviving
containers**. A sixth run flipped one environment value
(`EA_EXECUTOR_DEFAULT=coder`) and sent the same request through the
identical gateway → manager → queue path to the coding harness, which
produced a genuine commit (`7c9a32c` on the task branch: a healthz
handler plus its tests) before the switch was restored.

The flip itself carries a V2 lesson worth naming here: the executor is a
per-milestone responsibility, and the install stage that owns it
re-asserts the choice on every run and hard-fails if it cannot apply it —
because an earlier gate run silently exercised the stub executor when a
stage-skipping re-run skipped the stage that set the switch (ledger entry
11; the full story is Chapter 12's).

## 10.4 What the V2 build changed, and what it deliberately did not

**Kept, and re-proved under load:**

- **Immediate acknowledgment, asynchronous result.** The gateway answers
  in about a second with an ID; the work arrives later as a report.
  Synchronous execution remains the rejected alternative, for the same
  reasons as in the first build: long tasks would hold connections hostage, and the
  human would be locked out of the thinking layer precisely when they
  need it most. A handoff is not a session.
- **The registrar is code, not a model.** Matching, validation, policy —
  lookup-and-verify jobs. Fast, repeatable, and debuggable at a line.
  Every root cause in the V2 ledger (Chapter 12) is diagnosed to an exact
  defect in an exact file, and the deterministic front door is part of
  why.
- **The strict schema is the door policy.** Incomplete or malformed
  requests are refused loudly, with the missing or out-of-bounds field
  named. Doors that guess are doors that leak; V2 added no guessing.
- **A single request is a single task — for now.** Decomposition is the
  Chief of Staff's job, and the pipeline already accepts the multi-package
  shape without modification.

**Changed — exactly one thing, and not for the door's sake:**

- **The publish path is queue-direct.** The first build's manager published through the
  shared `agent.tasks` topic exchange. V2's manager publishes directly to
  the `ea-tasks` queue (default exchange, routing key = queue name). This
  was forced by coexistence, not by front-door design — both
  organizations' bridges bound the shared exchange, and first-start won.
  The full story — the race, the observed takeover of two V2 tasks by
  the first build's pipeline, the fix, and its honest trade-off (capability-based
  topic routing is deferred) — is Chapter 11's centerpiece, and the
  book's.

**Built as a shelf, waiting for its cargo:**

- The `ea-tasks` queue was declared durable **with `x-max-priority: 3`** —
  the queue-side argument for a `priority` field that no publisher sends
  yet. The field and its consumer (the manager's validation and
  pass-through) land in one gated change with the Chief of Staff
  milestone, per the platform design's field-plus-consumer rule; the
  queue argument was declared once, at the rename, so it never has to be
  declared again. The shelf is built. The cargo arrives with the next
  milestone.

## 10.5 The next milestone: the Chief of Staff, designed and waiting

The first book's Chapter 10 ended on a design question: *should the greeter be a
person or a program?* — and answered it with an architecture. This build carried
that answer through three design reviews, an owner decision record, and
an Architecture Decision Record, to the point where the answer is fully
specified. What follows is the **standing design** for milestone
**TP-V2-M1** — the next thing this project will build. It is design, not
history: none of it is deployed, and no request has ever flowed through
it.

**The resident agent.** A persistent Hermes Agent profile on the
front-of-house VM — the bus-org **chief-of-staff** persona from the
roster — sits between the unchanged gateway and the manager. It is
**propose-only**: it converses with the owner (from the Hermes Desktop,
which registers the VM-Xa gateway as a named remote connection with
session-token auth), understands the request in business language, and
decomposes it into proposed work packages — `agent_ref`, behavioral
specification, priority, TTL, dependency edges — selected from the roster
by judgment, not keyword. Its approval mode is **ask-before-submit**:
nothing is sent until the owner approves, and ambiguous triage produces
exact questions, never guesses. Autonomous submission is a later,
separately gated milestone.

**The code stays the door.** The manager validates every proposal exactly
as it validates any other request — roster existence, priority enum,
payload integrity — and the mechanical matching path remains as the
fallback when the CoS is unavailable or the request arrives already
structured. One line, carried from the first build and sharpened by every reliability
lesson since: **judgment proposes, code disposes.**

**The two-tier work board (ADR-0001).** The CoS's work state lives in two
deliberately different places:

- **Tier 1 — the master plan, on an external tracker** (GitHub Issues by
  default; the exporter is tracker-agnostic, so Azure DevOps or Jira are
  swap-in targets). A dedicated exporter component performs all tracker
  I/O and holds the tracker credential — the CoS never does. The master
  plan is the *plan of record*: it survives a total VM-Xa loss by
  construction, the owner reviews the proposed decomposition in it before
  approving, and its history is the **intent audit trail**.
- **Tier 2 — the working set, on the CoS's local Hermes board.** The CoS
  pulls a subset of the master plan — unblocked, priority-ordered, within
  the concurrency window — and drives that subset through the approval →
  submit → report loop. The local board is a **cache, not a record**.

Neither tier can start work — **the desk is never the door**. An item
becomes executed work only through the owner's approval → gateway →
manager validation → queue, and the gate will assert this negatively: a
proposal that was never approved produces zero submit calls, and no code
path may move a card to "submitted" except the approval flow. After any
reboot or restore, a card whose approval state is ambiguous goes
fail-safe to no-submit and surfaces to the owner — approved-but-unsubmitted
work is never reconstructed optimistically, and approval is recorded on
the card *before* any submit attempt, so the crash window is
deterministic.

**The credential contract.** The CoS profile holds exactly four things: a
CoS-class model token through the llm-proxy (so the highest-spend actor
stays inside the proxy's spend cap), the desktop's session token, an
ordinary gateway API credential for submitting approved work, and a
Hindsight write token (the CoS is the memory system's writer — the
pointer-store convention has an enumerated writer). Explicitly denied: no
GitHub token, no queue access, no direct manager access beyond the
gateway API.

**The gate that will make it real.** TP-V2-M1 is a strict gate: twelve
structural assertions — including reboot survival with no orphaned
approved-but-unsubmitted work, desktop reconnection after that reboot,
and the negative no-submit-without-approval test — plus a **judgment
corpus**: a versioned set of fixed requests with expected routing
outcomes (already written into the repo, machine-checkable at 100% for
the fields the pipeline consumes, owner-reviewed for the qualities no
score should pretend to measure). Plus one end-to-end: a market-analysis
request → decomposition → owner approval → parallel packages → reports →
one aggregated human answer → a corrective follow-on issued mid-flight
without ever interrupting a running executor.

**The honest status line:** the design documents are committed; the
corpus fixtures exist; the queue shelf is built; the five milestones
beneath the CoS (M0–M5) are built, gated, and signed. The CoS profile
itself is not deployed, the exporter does not exist, the desktop
connection is not registered, and TP-V2-M1 has not been run. The
milestone discipline this book keeps preaching applies to V2's own next
step exactly as it applied to everything before it: none of it counts
until the gate signs.

## 10.6 What this buys

With the front door standing as built:

- The HITL's experience remains *one sentence in, one structured answer
  out* — proven live, five acceptance runs and a coder-routed commit
  deep, on an estate where another organization was running the whole
  time.
- Every delegation still crosses exactly one audited boundary, carrying
  exactly one identity, returning exactly one artifact trail — now
  doubled across two organizations that never cross each other's paths
  (Chapter 11).
- The thinking layer stays cheap, safe, and human-paced; the execution
  layer stays durable, credentialed, and machine-paced; and the one agent
  who would live in both — the Chief of Staff — is specified so that its
  only power is *the power to propose through the same door everyone else
  uses*.

One chapter remains in Part II — the estate both front doors share, and
the rulebook that lets two whole organizations live on it at once.
