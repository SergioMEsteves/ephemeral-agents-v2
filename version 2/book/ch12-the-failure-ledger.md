# Chapter 12 — The Failure Ledger

> **In plain terms.** This is the chapter where the V2 build admits everything.
> Thirteen distinct defects were found and root-caused while re-building the
> organization beside its predecessor — far fewer than the ~35 the first build
> produced, which is itself a finding: the first book's rules were pre-applied
> where the design said they should be, and most of them held. Each entry is
> told in the first ledger's format — *symptom → wrong assumption → root cause →
> the rule now followed* — one numbered entry per issue, in build order
> (`version 2/V2-issue-ledger.md`). If you read one technical chapter of the
> V2 book, read this one.

## 12.1 The taxonomy: the same five classes, a different distribution

The first book's ledger chapter sorted ~35 defects into five
classes. Every V2 entry was sorted the same way, so the two builds can be
compared. The honest histogram:

| Class | This build's share | Entries | First build's share | Character |
|---|---|---|---|---|
| **C1 · Contract mismatch** | ~31% (4) | 5, 6, 9, 10 | ~40% | Two parties disagreeing about names, shapes, or fields — in V2, half of these are *checkers* disagreeing with what they check |
| **C2 · Deployment context** | ~46% (6) | 1, 3, 7, 8, 11, 12 | ~25% | Code correct in one environment, wrong in another — coexistence made this the build's dominant risk |
| **C3 · Timing and race** | ~8% (1) | 13 | ~15% | Components correct but assuming the other acts "immediately" |
| **C4 · Third-party semantics** | ~8% (1) | 2 | ~15% | External services behaving differently than assumed |
| **C5 · Estate drift** | ~8% (1) | 4 | ~5% | The real world changing underneath the system |

Three honest caveats before anyone reads the percentages as law. First, *n*
is 13 against the first build's ~35 — the ratios are coarse, and the stories in §12.2
carry more weight than the histogram. Second, entry 2 genuinely spans two
classes: its compose-recreation half is C2, its embedded-DNS half is C4; it
is filed under the half that surprised. Third, the first build's proud observation —
"almost no defects were logic errors inside a component" — does **not**
fully carry: entry 10 is a bug in the manager's own publish call site, and
entry 1 is a bug in a script's output. What *does* carry is the mechanism:
the components embodying the thesis (durable engine, issuer, memory
contracts) still never failed once built. The new defects clustered at the
*coexistence* seams — compose names, shared networks, shared exchanges,
credentials that outlive scripts — which is exactly where a second
organization standing next to the first should put pressure.

The distribution's most useful signal is what shrank. C3 and C4 nearly
vanished, and that is the first build's rules visibly working: margins around grace
periods, propagation-aware revocation checks, and translate-at-the-boundary
discipline were pre-applied, and the timing class that cost the first build ~15% cost this build
one late-night entry. The class that *grew* is C2 — because the build's
defining constraint was not "make it work" but "make it work **next to**
the working thing," and every assumption that was safe in a single-tenant
estate became a defect in a shared one.

## 12.2 The thirteen stories, by class

### Class C1 — contract mismatches

**5 · A literal broker password tracked in three composes.**
*Symptom:* during the deploy-v2 wiring review, the m1/m2 composes carried a
literal 16-character broker password in `RABBITMQ_URL` under a comment
claiming it was interpolated from `.env`. *Wrong assumption (two layers):*
that the de-identification sweep verified "zero credentials" — its pattern
did not match URL-embedded credentials — and that every later read showed
the truth: the terminal's `***` masking made the literal *look* like a
placeholder, so it passed through three reviews unnoticed. *Root cause:* the
m5 compose got the interpolation treatment; m1/m2 got only the comment
claiming it. *The rules:* credential sweeps must include URL-embedded
forms, verified byte-level, not display-level; and a comment claiming
interpolation must be backed by a byte-level check that the literal is
absent — **comments are not evidence.** (Fixed same day; verified zero
credential bytes in either repo's tracked files; no rotation needed — the
tracked value was stale.)

**6 · The bridge could not consume `ea-tasks` (PRECONDITION_FAILED).**
*Symptom:* the m1 gate failed at its first test — zero messages consumed —
with `inequivalent arg 'x-max-priority'`. *Wrong assumption:* that the
consumer's own queue declare did not need to mirror the canonical
declaration. *Root cause:* RabbitMQ rejects inequivalent re-declares; the
bridge declared `ea-tasks` without `x-max-priority: 3`. *The rule:* every
queue-declare site must byte-match the canonical declaration; a queue-shape
constant lives in one place per service.

**9 · A committed fix that never existed.**
*Symptom:* the manager image rebuilt from committed source did not compile
(`undefined: EnvTasksQueue`), and the queue-direct fix was absent from the
commit that claimed it. *Wrong assumption:* that `git add services/manager`
had committed the source. *Root cause:* `.gitignore` binary patterns
(`services/**/manager`, `…/gateway`, `…/adapter`) matched the *directories
holding the sources*, silently untracking whole trees — and `git status`
showed a clean tree, so nothing looked wrong. *The rule:* ignore patterns
that hide a directory carry explicit source-tree negations, verified by
`git check-ignore` on every file a milestone claims to commit; **a clean
tree is not evidence of tracked sources.**

**10 · The routing key was the capability string.**
*Symptom:* with the exchange unset, the manager published to the default
exchange with the agent-capability string as the routing key — messages
silently unrouted, no error anywhere. *Wrong assumption:* that clearing the
exchange alone was the fix. *Root cause:* the publish call site kept the
old routing key; against the default exchange it must be the queue name.
*The rule:* publish-mode constants (exchange, routing key) change together
and carry a test asserting the effective routing target.

### Class C2 — deployment context

**1 · A netplan write that would orphan a VM at reboot.**
*Symptom:* the chassis apply left `/etc/netplan/01-netcfg.yaml` with
`unknown key 'version'` — network survived in memory, but a reboot would
have stranded the role VMs. *Wrong assumption:* that the first build's install
script's heredoc was copy-safe — it had never been exercised on a clean VM,
because the first build's baseline was captured on machines that already had netplan
configs. *Root cause:* the emitted block lacked the `network:` root key.
*The rule:* any script that writes a config file is verified against a
real parse (`netplan apply` / schema validation) **in the same run**, and
the fix carries a byte-level check — display-rendered file contents are
not evidence.

**3 · A fresh credential versus a persistent volume.**
*Symptom:* after the chassis apply, the workflow engine failed with
`password authentication failed` — the install minted a fresh DB password
while the existing data volume still held the old one. *Wrong assumption:*
that `.env` generation is side-effect-free. *Root cause:* the DB password
lives in the data volume, not the env file; the script regenerated one side
of a pair. *The rule:* before minting a credential, check for a persistent
volume that outlives the script; when one side of a volume/env pair
changes, align the other and say so in the log. (Owner decision on the
spot: preserve the predecessor's credentials through coexistence; the
volume side is authoritative when old, the env file when new.)

**7 · The m2 gate ran the wrong executor.**
*Symptom:* the first m2 gate run failed — real executors spawned, exited 2
with unstaged environment. *Wrong assumption:* that the m2 compose could
carry the M5-era executor default for forward-compatibility. *Root cause:*
the compose-evolution rule was violated — a milestone's compose carries
only that milestone's config; future-era settings land with the milestone
that owns them. *The rule* is exactly that. (This entry wrote §14.6 of
this book.)

**8 · The hindsight compose took over the predecessor's stack.**
*Symptom:* deploying the V2 memory stack replaced the first organization's containers and
reused the first build's data volume — the first organization's memory system went down. *Wrong
assumption:* that compose project and volume names inherited from the first build were
safe. *Root cause:* the m4 compose kept the project name `hindsight` and
the volume name. *The rule:* every V2 compose sets `name: ea-*`, `ea-*`
containers, and an own volume; the restoration sequence (first organization up, this build up) is
part of the fix, not an afterthought. One compose `name:` was the entire
difference between coexistence and takeover.

**11 · Injections that silently exercised the stub executor.**
*Symptom:* the failure injections "succeeded" — with the blocking fault
provably loaded and verified live, no failure-shaped report ever appeared.
*Wrong assumption:* that the E2E's real-executor success implied the
injections ran the real executor too. *Root cause:* the lifecycle's
executor default was unset, so the executor resolved to the stub pin — the
M5-era switch documented in a comment was never implemented, and the
stage-gate re-run skipped the stages that would have applied it. *The
rules:* every stage-gated run re-asserts the preconditions the skipped
stages would have established (m5's §2' stage, hard-failing when not
applied); and a test whose verdict depends on which executor runs asserts
that executor **by name**.

**12 · A runbook that was still stub-era.**
*Symptom:* five defects in one runbook — injections published a capability
that did not exist in the catalog, waited a fixed 45 s for reports that
take ~13 minutes, killed by name instead of PID, and blocked the wrong
netfilter hook (container egress traverses `forward`, not host `output`).
*Wrong assumption:* that the first-build-era runbook mechanics survived the executor
change. *Root cause:* it was never re-derived against real executors. *The
rule:* every wait polls the observable (the report file); kills are by PID
with a docker-kill fallback; fault injection blocks the path the fault
requires; the injected capability is a real catalog reference.

### Class C3 — timing and race

**13 · A token check that aborted on an undefined variable and raced
revocation.**
*Symptom:* the hardening stage died silently between "issued token → 200"
and the revoke step (`tok: unbound variable` under `set -u`); an earlier
run's immediate post-revoke check read 200. *Wrong assumption (two):* that
the post-revoke check used the variable the pre-revoke check used, and
that revocation is instant. *Root cause:* an undefined variable, plus
revocation propagation measured in seconds. *The rule:* both halves of a
lifecycle check read the same variable; a revocation check sleeps past
propagation (5 s) before asserting.

### Class C4 — third-party semantics

**2 · The workflow engine fell off the shared network on recreation.**
*Symptom:* after the chassis apply, the worker and bridge could not resolve
`temporal` (embedded-DNS SERVFAIL) — the predecessor's path was down while
every container showed `Up`. *Wrong assumption:* that declaring the
external network next to the implicit default was enough. *Root cause (two
independent bugs):* the first-build-era stack wired the shared network with a
manual `docker network connect`, which every compose recreation silently
drops; and a container attached to two networks with the same alias on
both makes Docker's embedded DNS fail peer lookups — so the stack cannot
merely *add* the network either. *The rule:* shared-network membership is
compose-declared, never attached by hand; services live **only** on the
shared network, aliases declared — the broker already followed this
pattern, and it is now the template for every multi-service stack in V2.

### Class C5 — estate drift

**4 · The registry VM drifted to a new address.**
*Symptom:* the registry VM became unreachable at its documented address
while the hypervisor showed it running; it had silently taken a new DHCP
lease, and its UI container had vanished entirely (re-created from its
compose). *Wrong assumption:* that the fourth VM's address was stable — it
was never in the three-VM chassis matrix. *Root cause:* no static netplan,
no ssh alias. *The rule:* all four VMs get static netplan + ssh alias at
S0, and a **reboot-and-reach** test is the chassis close-out event.
(Closed same day: static pin applied, the DHCP installer config removed so
it can no longer race the pin, verified by reboot-and-reach — ssh alias,
registry API 200, UI 200, catalog intact.)

## 12.3 What the rules bought

The V2 build's most important process finding is that **every root cause
above was caught by a gate or a byte-level check, not by a production
symptom.** The gitignore source-masking was caught by the m5 image build;
the routing-key bug by re-reading the diff; the stub-executor injection by
an instrumented block-load log; the tracked credential by a wiring review.
Not one entry was discovered by "the system was down." That is the staged
build (platform design §9.6) earning its cost: thirteen entries across
five milestones, each converted into a rule the *next* stage enforced —
entry 7's rule is why entry 11 could even be recognized, and entry 5's
byte-level rule is what finally caught what display masking had been
hiding all along.

The four meta-rules carried from the first build, with V2 amendments:

- **Idempotent, stage-gated installs** — with the new sub-rule (entry 11 /
  findings §4.3): a stage gate must *re-assert the preconditions the
  skipped stages would have established*, not merely check that earlier
  stages once passed. `M5_FROM=5` re-runs were silent about the executor
  default until §2' made re-assertion a hard gate.
- **Root-cause-only fixing** — thirteen defects, zero standing workarounds;
  the one takeover incident (entry 8) ended with a restoration sequence
  and a rule, not a hand-patched estate.
- **Ledgers, not memories** — every fix committed with its rationale; this
  chapter is a re-reading of `version 2/V2-issue-ledger.md`.
- **De-identification by construction** — amended by entry 5: sweeps are
  byte-level and include URL-embedded credential forms; and by findings
  §4.4: terminal masking is a *debugging hazard in both directions* — it
  twice made a correct file look broken and twice made a broken file look
  fine. Verify file contents with a byte-level read, never with display
  output.

## 12.4 What the ledger says about the thesis

The findings report counts four of the thirteen entries as classes the first build's
book had already predicted — volume/env pairs (3), network attachment (2),
tracked literals (5) — rules written into the V2 design *before* the build
and still earning their keep; the other nine were genuinely new. That ratio
is the fair measure of a second build: the first book prevented about a
third of the second build's failures by prescription and could not have
named the rest, because the rest are defects that only exist when *two*
organizations share one estate.

The thesis mechanism — each wall falls once its structure exists, and
stays fallen — held again. No wall re-appeared. What re-appeared was
construction noise, now of a new species: coexistence noise. And the noise
was quieter by half: thirteen entries instead of ~35, in one-third of the
calendar time (three days against four), with every one caught before it
could ship.

## 12.5 The one-paragraph version

The V2 build found 13 defects across five milestones in three days —
against the first build's ~35 in four. Nearly half were deployment-context
defects (coexistence: compose names, volumes, executor eras, stub-era
runbooks); a third were contract mismatches, of which half were *checkers*
mismatching what they check (sweep patterns, ignore patterns) rather than
components mismatching each other; and one each came from timing, a
third-party's dual-network DNS semantics, and the estate moving underfoot.
The five rules worth carrying forward from V2: *byte-level verification,
never display output* · *a comment claiming a property is not evidence of
it* · *a milestone's config carries only that milestone's era, and a
stage-gate re-runs assert what the skipped stages would have set* · *every
V2 compose is born `ea-`-named with an own volume, and publishes
queue-direct* · *a checker is a component — its pattern is a contract too.*
A system rebuilt under those rules was gated, signed, and left running —
beside the first one, untouched.
