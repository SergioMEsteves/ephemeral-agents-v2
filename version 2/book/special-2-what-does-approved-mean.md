# Special 2 — What does "approved" mean?

> **In plain terms.** "Approved" is the strongest word in this system,
> so it should mean exactly one thing: *you read a concrete plan and
> said yes to that plan — before anything was submitted.* This piece
> follows an approval from your screen to the queue, explains the
> fingerprint that pins a submission to what is on record, states
> plainly what that fingerprint can and cannot prove, and shows why a
> card is closed by a report — never by the worker that did the work.

## The journey of an approval

Follow one real request — the V2 acceptance test, *"add a health
endpoint to the POC project"* — from your screen to the queue. The
names it needs are defined as they appear; the three-lists picture
(tracker, queue, board) is Special 1's subject.

1. **You ask.** From the Hermes Desktop you send the request into the
   chief-of-staff's (CoS) conversation on the agent machine. Nothing is
   submitted; there is nothing to submit yet.
2. **The CoS plans.** It breaks the request into work packages — which
   role does what, what depends on what, how urgent each is — and
   publishes the complete plan to the **tracker**, the external list
   where the plan of record lives.
3. **You review — in the tracker, not in chat.** The plan sits as
   concrete items you can read item by item: *add a `/health` endpoint
   to the coder's target repo; a verification task to follow it* —
   whatever the decomposition actually is. The review surface is a
   list, on purpose: lists are hard to approve without reading;
   chat scrolls are easy.
4. **You approve — a specific version.** "Approved" means: *this
   decomposition, this version of it.* If you ask for changes, the CoS
   produces a new version of the proposal; the old version's id is
   void and can never be submitted.
5. **The CoS pulls its working slice and submits.** Only now does
   anything move. The approved, unblocked items are pulled onto the
   CoS's local board (the notepad — it can start nothing by itself),
   and each package is submitted through the **gateway**, the front
   door. The **manager** — the deterministic checker behind the door —
   validates it: the named role exists in the roster (the system's
   catalog of available roles), the priority is one of the three real
   values, the package is complete. Only then is it published to the
   queue.
6. **A worker runs; a report comes home.** A short-lived worker picks
   up the task, does it, reports through the gateway, and ceases to
   exists. The CoS reads the report, writes a memory pointer — a small
   note of what was learned and where the result lives, for future
   tasks to find — rolls the results up, and gives you one human
   answer.

Step 4 is the whole safety story, and it has a name:
**ask-before-submit.** The CoS proposes; you decide; only then is
anything sent. It never submits without your yes, and when its own
judgment is unsure it asks you exact, clear questions instead of
guessing. An autonomous mode — the CoS submitting on its own — exists
in the design only as a *later, separately gated* change, deliberately
not built yet.

## The fingerprint: what "approved" is pinned to

Every submitted work package carries a **hash** — a fingerprint
computed from the exact text of its specification (SHA-256, a standard
fingerprint function, over the text byte for byte). The manager
records the fingerprint and checks it. Two checks, both narrow and
both deliberate:

- **Retry integrity.** If a submission's outcome is unclear — the
  gateway timed out, but did the order land? — the CoS retries under
  the *same task id*, the package's name, which never changes across
  retries. The manager accepts the retry only if the fingerprint
  matches exactly. A matching duplicate is absorbed (a retried order
  is not run twice); a different package under the same id is
  rejected. The payload cannot be silently swapped between attempts.
- **Reject and surface.** Any non-matching payload is rejected *and
  reported to you* — never quietly accepted, never quietly dropped.

### The honest limit

Here is the part stated without varnish: **the fingerprint is
tamper-evidence, not tamper-prevention.** The CoS computed the
fingerprint from the same text it wrote. If the CoS itself were wrong
— malfunctioning or manipulated — it could in principle fingerprint
text you never approved. So the fingerprint proves that *the submitted
text is unchanged between attempts and matches what is on record*; it
cannot prove that the text is *what you approved*.

What actually stops an unapproved submission is simpler and older: the
approval loop itself. Nothing is submitted unless you approved it; the
board cannot start work (Special 1); and the build's gate includes the
negative case — a proposal that was never approved must produce zero
submission calls, and a voided proposal id cannot be submitted at all.

A later, separately gated change narrows the gap further: the gateway
will record the fingerprint *at the moment you approve*, so the pin is
sourced from your approval rather than from the CoS. That upgrade was
designed and deliberately deferred — the gateway is unchanged in this
milestone — and the deferral is on record with its reason. Saying the
limit out loud now is what makes the later upgrade a plan rather than
a surprise.

## Why the report closes the card, not the worker

The worker that did the job is built to disappear: created for one
work order, it works, reports, and is destroyed — nothing survives but
the artifact it committed and the record of the run. A worker cannot
close its own card, for the same reason it cannot open one: the card's
truth lives with the gateway and the queue, not with the transient
worker. What the worker *did* is the content of its report; whether
the work *happened and counts* is recorded by the pipeline — the part
of the system that cannot have an opinion.

So the card moves through its last states only on the gateway's word:

- **In-flight** when the gateway acknowledges the submission.
- **Reported** — done — when the report event arrives from the
  gateway's reports endpoint. Only then is the card closed and rolled
  up.

If the report never comes — the task outlives its time limit, the
worker dies mid-task — the card does not quietly close. The CoS keeps
asking the gateway past the deadline, then surfaces the task to you as
failed, with the last known state. **Silence is never taken for
success.**

This is the same asymmetry that opens the card. The agent proposes;
the code disposes — and, just as firmly, the code reports.

## The one-line version

> "Approved" means: you read the concrete plan in the tracker and said
> yes to that exact version, before anything was submitted. The
> fingerprint on the submitted package proves it was not swapped in
> flight — and, honestly, cannot prove more than that; the approval
> loop itself is the lock. And the card closes when the report
> arrives — never by the worker's word, never on silence.

---

*Where this is written down: `V2-M1-cos-design.md` §2 (Q2, ask-before-
submit), §6 (the approval and results loop), §7 item 10 (the approval
hash, its two checks, and the honest limit); the field-and-consumer
rule in `V2-platform-design.md` §5; the gate assertions TP-V2-M1 §7,
items 9 and 10. The board side — why neither list can start work — is
Special 1.*
