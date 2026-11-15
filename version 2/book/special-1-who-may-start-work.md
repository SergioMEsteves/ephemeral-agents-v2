# Special 1 — Who is allowed to start work?

> **In plain terms.** The system keeps three lists of work, in three
> places, and each list tells the truth about a different thing. The
> **tracker** tells you what is *planned*. The **queue** tells you what
> is *actually happening*. The **board** — the helper agent's own
> notepad — tells you nothing on its own; it is a convenience copy, not
> a record. And here is the rule this piece is about: **none of the
> three lists can start work.** Work starts in exactly one way — you
> approve it, it is submitted through the front door, the checking
> program accepts it, and only then does it reach the queue. The rule
> has a name: *the desk is never the door.*

## Who is who

Four names appear throughout; here they are once, in plain words.

- **The chief-of-staff (CoS)** — a long-lived AI agent that talks with
  you, turns your request into a plan of work packages (who does what,
  in what order, how important), and manages the packages through to
  completion.
- **The tracker** — an external list of planned work. GitHub Issues by
  default (Jira or Azure DevOps can be swapped in; the choice is a
  setting, not an architecture). It lives off the agent's machine.
- **The gateway** — the front door: a small, stateless program that
  accepts a work order and passes it inward. It is the only way in.
- **The manager** — the checker behind the door. It validates every
  work order against fixed rules before anything may proceed. It is
  code, not a model, and it never has an opinion.

## Three lists, three truths

**1. The tracker holds the plan.** When you give the CoS a request, it
does not start working. It writes a plan — every work package it
intends to create, the role for each, the dependencies between them —
and publishes the plan to the tracker. The tracker is the **plan of
record**. Because it lives off the agent's machine, the plan survives
even the total loss of that machine. It is also where you review a
proposed plan before approving anything, and its history is the
*intent* trail: what was intended, in what order.

**2. The queue holds the execution.** Once a work order passes the
gateway and the manager's checks, it lands on a waiting line. From
there a short-lived worker picks it up, does exactly that one task,
reports, and disappears. The queue — with the gateway and manager
records around it — is the **execution truth**: what was actually
submitted, what actually ran. Nothing in the system outranks it. When
the board and the queue disagree, the queue wins. Always.

**3. The board is a notepad.** The CoS keeps a small board of its own —
cards in columns: proposed, approved, submitted, in-flight, reported.
It does not hold the whole plan. It holds a working slice: the items
that are unblocked, in priority order, and few enough to run at once
(five agents in flight, by default). The board is a **cache** — a
convenience copy between the plan and the execution. It is
authoritative for nothing. It can be lost and rebuilt from the tracker.

This division is decision D12-rev of the V2 design, recorded in full in
ADR-0001. One sentence carries it: *the tracker is authoritative for
the plan; the gateway, manager, and queue are authoritative for
execution; the local board is a cache between them.*

## The desk is never the door

Think of the CoS as a chief of staff at a desk, and the gateway as the
only door out of the building. The desk — both of its tiers, the
tracker copy and the notepad — can *prepare* work all day: draft
packages, order them, hold them, revise them. But a card becomes real
work only when it walks through the door:

> **your approval → the gateway → the manager's checks → the queue**

Neither tier of the board can skip this, and that is a property of the
wiring, not a promise about good behavior:

- The CoS holds no queue credentials and has no queue access by design.
  It speaks the gateway's API, like any other client, and nothing else.
  (A later hardening step adds a network-level lock on top; the design
  states this honestly rather than claiming it early.)
- A card moves to *submitted* only as a **reflection** of a gateway
  acknowledgment — never as a cause. If a card says "submitted" but the
  gateway never acknowledged anything, the card is simply wrong, and
  the next check against gateway truth will fix it.
- The build's test procedure asserts this directly: **no code path may
  move a card to "submitted" except the approval flow.** The board
  reflects; it never drives.

The agent proposes; the code disposes. The desk can want things all
day. Only the door can make them happen.

## How a card closes: approval → submit → report

A card walks through its states, and each move has one named cause:

1. **Proposed** — the CoS drafts a work package. Nothing has been
   sent; you have not been asked yet.
2. **Owner-approved** — you said yes. The approval is *written on the
   card before anything is submitted*, so that if the machine dies in
   the next second, the record of your yes survives.
3. **Submitted** — the package went through the gateway and the
   manager accepted it. This state is written only *after* the gateway
   acknowledges. If the gateway is silent, the card stays at "approved
   but not submitted" and surfaces to you — it is never guessed at.
4. **In-flight** — a worker has picked it up. Again a reflection: the
   gateway's status told the board so.
5. **Reported** — the report came back through the gateway. Only now
   is the card done, and it rolls up into the answer you receive.

Two details in that walk deserve a pause.

**Your approval is recorded before the submit attempt.** This ordering
is deliberate. The dangerous window — a crash between "the owner said
yes" and "the order went out" — becomes *deterministic*: after a
crash, a card with your approval recorded is completed through the
normal submission flow (your yes is honored); a card whose approval
state is unclear goes **fail-safe to no-submit** and is surfaced to
you to decide again. The build's tests kill the machine inside exactly
this window and check both halves of that rule.

**Nothing closes on silence.** If a report never arrives — a task
outlives its time limit, a worker dies mid-task — the CoS keeps asking
the gateway past the deadline, then surfaces the task to you as failed
with the last known state. A card is never quietly closed, and never
closed by the worker's own word. (Why the report — not the worker — is
the closer is Special 2's subject.)

## When the three lists disagree

They will, sometimes, and the rule for who wins is short:

- **Tracker vs. board:** the tracker wins. Plan content flows *down*
  into the board only when the CoS explicitly pulls it; status flows
  *up* from the board to the tracker. If the tracker is unreachable,
  the CoS keeps working locally and syncs when it returns — the plan's
  durability does not depend on being online.
- **Queue vs. board:** the queue wins, every time. On boot and on
  demand, the CoS re-checks every submitted item against gateway truth
  and corrects the board to match.
- **A damaged board:** the board itself is not trusted to be intact.
  If it comes back damaged or unreadable, the response is always the
  same — submit nothing, surface it to you. A damaged notepad is a
  reason to stop, not a reason to improvise.

## Why it is built this way

- **So that judgment cannot start work.** The one thing an AI agent
  must never be able to do alone is turn a plan into action. The
  wiring gives it the desk and withholds the door.
- **So that the plan survives the machine.** The plan lives off the
  machine that does the work; the notes that live on the machine are
  replaceable.
- **So that you review the plan where plans live.** Your approval
  happens against the tracker's decomposition — a concrete, reviewable
  list, not a chat scroll — which makes it much harder to approve out
  of habit without reading.
- **So that no new credentials were needed.** The small component that
  publishes to the tracker (the *exporter*) holds the tracker key. The
  CoS itself never does. Adding the tracker added no keys to the agent.

## The one-line version

> Three lists, three truths: the tracker is the plan, the queue is the
> execution, and the board is just a notepad. And the desk — neither
> tier of it — is never the door: only your approval, through the
> gateway and the manager, can start work.

---

*Where this is written down: `adr-0001-cos-work-board.md` (the owner's
decision record); `V2-M1-cos-design.md` §2 (D12-rev) and §6; the gate
assertions TP-V2-M1 §7, items 7 and 9. The approval side — what "yes"
means and how it is pinned — is Special 2.*
