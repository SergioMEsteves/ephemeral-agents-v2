# Chapter 7 — The Executors

> **In plain terms.** Chapter 6 defined *who* does the work; the executor is
> the *body* they occupy. V1 established that there are bodies, and that a
> generic body becomes a specific specialist in about a second. V2's subject
> is different: **who is allowed to turn the real agent on.** The executor is
> now a switch with three positions — stub, hermes, coder — and flipping it
> is a per-milestone responsibility with a hard-failing, idempotent stage,
> because the build once ran a whole fault-injection campaign against the
> wrong body and everything "passed."

## 7.1 Carried forward: role ≠ body

The V1 design decisions hold unchanged in V2: a role is knowledge and
behavior (prose in the roster); a body is capability and plumbing (an
image). Two real harnesses — the general hermes executor and the code
executor — serve the whole roster; role files are hydrated at boot, not
baked at build; the boot self-report is the worker's first act and is gated
on. Nothing in this chapter revises that separation. What V2 adds is the
*control* layer above it: which body a spawned container occupies is a
configuration fact, and the build learned that configuration facts need
owners, assertions, and evidence just like everything else.

## 7.2 The three-position switch

The lifecycle spawns whatever `EA_IMAGE` pins and configures whatever
`EA_EXECUTOR_DEFAULT` names. Three positions exist:

1. **The stub** (`ea/executor-stub`) — a few dozen lines: echo the spawn
   config to stdout, write a marker file, sleep the TTL, exit 0, with
   injected failure modes (`exit-1`, `hang`) for the lifecycle gates. It
   has *zero agent logic*, and that is its purpose: it proves the
   lifecycle's mechanics — spawn, env injection, reaping, TTL, zero
   survivors — without any dependency on agent internals.
2. **Hermes** (`ea/hermes-ephemeral`) — the general executor: the V1
   hydration contract at boot (roster clone, role resolution, the three
   persona files, the self-report), then the real agent runtime, then a
   task report. Measured boot p50: **1433 ms** from container spawn to
   self-report ready, on the lifecycle's real spawn path.
3. **The coder** (`ea/claude-coder`) — the edit-ship harness: task branch,
   headless coding agent with explicit grants, commit with the task ID,
   push, report. The V2 acceptance run's commit — `7c9a32c` on the task
   branch, carrying a health endpoint and its tests — went through this
   position, over the identical gateway → manager → queue path.

The message contract deliberately has **no executor field**. message-v1
stays additive-only, and *which body runs a task is estate configuration,
not a property of the request* — the publisher does not get to choose its
own privilege level. The switch is one environment variable, owned by the
operator's milestone plan.

## 7.3 The switch is a per-milestone responsibility

V2's staged build made executor activation explicit, milestone by
milestone:

| Milestone | Executor state | Why |
|---|---|---|
| M2 | **stub only** — the compose pins `EA_IMAGE` to the stub and omits the default | The M2 gate proves lifecycle mechanics; no agent env exists yet |
| M3 | stub *default*, hermes/coder **available** — images loaded, the image switch and per-run secrets staged | The M3 gate exercises the real executors directly; the M2-path default stays conservative |
| M5 | **`EA_EXECUTOR_DEFAULT=hermes`** — flipped by §2' | The E2E and injection gates exercise the real organization |

The rule that makes this schedule work: **a milestone's compose carries
only that milestone's config; future-era settings land in the milestone
that owns them.** The build proved the rule bites — the first m2 gate run
failed its first two cases because the m2 compose carried the M5-era
default for forward-compatibility: real hermes executors spawned, found
unstaged m3-era environment, and exited 2 (ledger 7). A compose comment
promising a future state is not a future state; it is a live setting that
fires early.

## 7.4 The M5 flip: §2'

The flip is a dedicated stage in the m5 install, and it is built to be
boring:

- **Idempotent.** A small helper inserts `EA_EXECUTOR_DEFAULT: "hermes"`
  beside the image pin in the live m2-era compose if absent, and reports
  "already present" otherwise. Re-running the install never duplicates the
  setting.
- **Hard-failing.** After forcing the lifecycle to recreate, the stage
  inspects the *running* container's environment and asserts the default
  is applied — if the inspection does not show it, the install dies
  before any downstream gate runs.
- **Unconditional.** It runs on *every* invocation of the m5 install,
  outside the stage gates — including re-runs that skip the early stages.

That last property is the stage-gate lesson generalized (findings §4.3):
`M5_FROM=5` re-runs skip the stages that originally established the
executor default, so **a stage gate must re-assert the preconditions the
skipped stages would have established** — not merely trust that earlier
stages once passed. Preconditions are re-asserted, not remembered.

The stub is not removed at M5. It stays pinned and loadable as the
rollback position: flipping the default back is a one-line, one-container
operation, which is exactly what you want under a real executor misbehaving
mid-campaign.

## 7.5 Stub and hermes are behaviorally distinct

The two bodies differ in *every* observable a gate can check:

| Observable | Stub | Hermes |
|---|---|---|
| Boot to self-report | ~0 (echo) | p50 1433 ms |
| Work duration | sleeps its TTL | minutes (real run) |
| Report shape | success, always | artifact — or a failure-shaped report |
| Reaction to faults | none (faults cannot touch it) | fails with exit 2 and an error self-report |

The distinctness is the property that makes executor-blind testing
impossible, and the build needed the reminder. The M3 failure-path gate
proved hermes's failure behavior directly: an unreachable roster URL and an
agent ref missing from the catalog index each produced exit 2 with a
structured error self-report, while the control run booted in 644 ms and
loaded all three persona files. The stub, run against the same faults,
would have slept and reported success — because the stub *cannot observe
the estate*. A test that passes under the stub proves the lifecycle; only
a test that asserts hermes by name proves the organization.

## 7.6 Case study: the M5-era switch gap (ledger 11 and 12)

The build's own gate caught the failure this chapter exists to prevent,
and the case is worth walking because every element of it is structural.

**The symptom.** During M5 §5, fault-injection tasks were published while
outbound access to the source-control provider was blocked by the host
firewall — the block provably loaded, its rule count recorded in the
evidence stream. The tasks' reports came back success-shaped. Failure
injections that do not bite are worse than failures: the campaign *looks*
green while proving nothing.

**The wrong assumption.** That the §4 end-to-end run's hermes-path success
implied the §5 injections used hermes too. In fact the lifecycle's
`EA_EXECUTOR_DEFAULT` was unset, so the executor resolved to the stub pin
in `EA_IMAGE` — the M5-era default documented in m3's compose-evolution
comment had never been implemented by the m5 install, and the stage-gated
re-run (`M5_FROM=5`) skipped exactly the stages that would have applied it
(ledger 11).

**The root causes, two defects, one shape.** First: a *documented but
unimplemented* switch — prose in a compose comment stood in for a
mechanism. Second: a stage gate that forgot what it skipped. Both are
closed mechanically now: §2' implements the switch idempotently and
hard-fails on its own assertion, and it runs on every invocation.

**The runbook was stub-era too (ledger 12).** The injection runbook had
been written when the stub was the only body, and every mechanic failed
against real executors: it published tasks with a capability that was never
a real catalog ref (rejected at publish), waited a fixed 45 seconds for
reports that take ~13 minutes under hermes, killed processes by name
matching (names are not PIDs), and blocked the wrong netfilter hook —
container egress traverses the *forward* chain, not the host's *output*.
The re-derived runbook: every wait polls the observable (the report file)
instead of sleeping, kills by PID with a container-kill fallback, blocks
the path the fault actually requires, and injects only real roster refs.

**The result.** Re-run with the default applied: the provider block bites,
failure-shaped reports land within the polled window, zero survivors —
F1/F2 recorded PASS with the block's rule count in the evidence stream.
The two cases whose injections were absorbed by the estate's own recovery
policies (a mid-task kill met by the retry policy; a short TTL met by the
clamp-and-self-heal path) are recorded as CHECK-with-recorded-policy —
the same honest grading V1's gate used, and Part III's subject.

## 7.7 Design decisions and alternatives

**Decision: executor selection is estate configuration, not a message
field.** Alternative: let the work order name its executor. Rejected: the
message arrives from anywhere; the executor choice determines what the
worker can do, and privilege selection belongs to the operator's milestone
plan, expressed once in configuration — not negotiated per request.

**Decision: stub default until the milestone that owns the flip.** The
conservative default costs nothing (the stub is seconds) and makes every
pre-M5 gate independent of agent internals. The one time this was
violated, the gate failed within two cases (ledger 7) — the rule paying
for itself.

**Decision: idempotent action + hard-failing assertion.** The flip could
have been either, and the combination is the point: idempotence makes it
safe to re-assert on every run; the hard failure makes "already applied"
an *verified fact* rather than a hope. An assertion that dies the install
is the only kind that survives stage-gated re-runs.

**Decision: tests assert the executor by name.** Any gate whose verdict
depends on which body ran asserts that body — in the spawn env, in the
self-report, in the report shape. The stub/hermes distinction (§7.5) is
what makes such assertions cheap and unambiguous.

## 7.8 What this buys

The executor switch turns "which body runs the work" from an accident of
whatever the compose happened to carry into a **declared, owned,
asserted** responsibility: the stub proves the mechanics, hermes and the
coder prove the organization, and the milestone that flips the switch
proves the flip. The M5-era gap cost one gate cycle and produced three
standing rules; the acceptance request now walks the whole switch — stub
gates first, hermes end-to-end, the coder's commit `7c9a32c` at the end —
on one estate, beside the V1 organization's own live stack.
