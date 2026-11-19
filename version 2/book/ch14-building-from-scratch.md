# Chapter 14 — Building the V2 Estate from Scratch

> **In plain terms.** The first book's operator chapter answered *"if I hand you a
> server, can you build the whole thing?"* This chapter answers the harder
> question V2 set itself: *"can you build it **beside** a system that is
> already running — from committed files, in three days, without stopping
> the first one?"* The answer is yes, and this is the chapter a new operator
> reads first. Its spine is the committed runbook
> (`deploy/RUNBOOK-V2-BUILD.md`); this chapter tells the story and the
> lessons, the runbook carries the exact commands.

## 14.1 What you supply (the complete list)

Everything the runbook's stage 0 requires, collected **before** the first
stage runs — the runbook's own rule is *stop and ask if any item is
missing*:

| Input | Why |
|---|---|
| PVE host + 4 static LAN IPs (front-of-house, execution, memory, registry) | the estate is address-pinned; record the name-resolution choice in the m0 decision log |
| SSH keypair; the ops user authorized on PVE + all VMs, passwordless sudo | every script SSHes key-only, BatchMode |
| GitHub App (id + private key) | reused if rebuilding the same organization; a new org needs the ~5-minute manual App setup no automation can do |
| Roster repo + read token | the one agent catalog; layout contract cited in the runbook |
| llm-wiki repo + read token | shallow-cloned by executors at boot (D-wiki-git) |
| Embedding provider key (optional) | omit → zero-vector fallback (D-embed) |
| TTL/cap values | `EA_TTL_DEFAULT`, team cap |
| Model/provider key for the CoS | staged **only** as the llm-proxy provider key — the CoS never holds it |

Plus one workstation inventory: docker + buildx, Go ≥ 1.22, the `temporal`
CLI, `gh` (logged in), rsync, python3. The first artifact is the same as
the first build's and for the same reason: copy `hosts.env.example` → `hosts.env`
(gitignored), pin VMIDs/IPs from minute one, never let a second copy drift,
and run every script's check-only mode before its apply. The inventory-first
rule exists because the first build learned it three stages deep (the first book's ledger chapter, class C5) — and because V2's ledger entry 4 (the registry VM's DHCP
drift) is what happens to the one machine that was *not* in the matrix.

## 14.2 The rename micro-gate comes first

The single most V2-specific step precedes every install: the estate is
**born `ea-`-named** (`version 2/ea-rename-mapping.md`), executed as a
gated micro-gate *before* the build, not as a sweep after it. The reasons
are structural, not cosmetic:

- **The queue declaration is once-only.** `ea-tasks` is declared durable
  with `x-max-priority: 3` at the rename — RabbitMQ cannot add that
  argument later (OQ4's single declaration point). Renaming after the
  build would mean re-declaring queues under constraints the queue
  already forbids.
- **Images are verified by digest, not by trust.** The registry re-tag ran
  digest-identity checks per image and hard-fails on mismatch. (The honest
  correction the micro-gate recorded: only 3 of the 9 listed images were
  ever registry-resident — the other 6 are install-built and had nothing
  to re-tag; the script's image list was corrected to match reality.)
- **Coexistence rules get front-loaded.** Compose project names, volume
  names, ports, and labels were pinned in a checklist before any stack
  existed — a checklist that then held for five milestones, with exactly
  one violation caught and ruled (Chapter 12, entry 8).

The repo half of the gate (grep audit over V2-owned trees, mapping table)
landed first; the estate half — re-tag 3/3 digest-identical, stale
`agent.tasks.dlq` drained, `ea-tasks` declared — followed. Every V2-owned
component must be `ea-`-named before its first install; the baseline
`deploy/` layer keeps the first build's names deliberately, as the frozen evidence path.

## 14.3 The stage order (the runbook's spine)

Each stage runs `--check-only` first, then apply, then its gate; each gate
names the artifact it proves and is signed before the next stage opens.
The build is the runbook's editor — changes land in the same turn as the
stage that ran.

<!-- DIAGRAM: build-order-and-estate (owner-drawn) -->

| Stage | What it builds | Gate |
|---|---|---|
| **S0 Chassis** | 4 VMs provisioned, base OS, netplan, docker, ops user + sudo, UFW, network verification matrix | matrix green; **reboot-and-reach** as close-out (ledger 4) |
| **S1 Registry** | private registry + TLS + basic auth, GC policy (keep-last, disk alert), gitignored 0600 env | pull 200 · auth-negative 401 · push+delete · plain-HTTP rejected |
| **S2 Images** | the `ea/*` images — built or re-tagged digest-identically | per-image digest equality, evidence committed |
| **S3 Broker + engine** | `ea-tasks` family declared **once** (x-max-priority), temporal compose-declared on `ea-net` | queue visible with its argument; cross-VM AMQP publish test |
| **S4 Services** | topic-bridge, lifecycle, worker — all `restart: unless-stopped`, images digest-pinned | M1/M2 test scripts green under ea names (T1–T5; the first build's V-series) |
| **S5 Memory** | pgvector + hindsight on the memory VM, own volume, port moved off the first build's (8082 vs 8081), write/read token split | G1–G6 incl. data isolation from the first build's store |
| **S6 Front-of-house** | gateway + manager on the front VM (8083/8086 beside the first organization's 8080); CoS profile per the M1 §5 allow-list | manager validation e2e + credential assertion (exactly the allow-list, denial list negatively asserted) |
| **S7 Desktop + smoke** | desktop→CoS gateway connection; contract suite; judgment corpus; one approved end-to-end | **TP-V2-M1**: assertions 1–12, corpus Layer-1, e2e green |

The staged build as executed ran S0–S6 (M0–M5) to a signed TP-M5; S7 is
the CoS milestone's gate, next per Chapter 13.

Two runbook rules deserve their own telling, because both were *written by
a V2 ledger entry before the build needed them a second time*:

### The clean-VM lesson: configs are verified by parse, not by eyeball

Ledger entry 1 is this chapter's cautionary tale. The chassis script's
netplan writer was inherited from the first build and had never been exercised on a
clean VM — the first build's baseline was captured on machines that already had
working configs. On clean VMs it emitted a file missing the `network:`
root key: valid enough to survive in memory, fatal at the next reboot.
The rule now enforced: **any script that writes a config file is verified
against a real parse in the same run, and the fix carries a byte-level
check** — display-rendered file contents are not evidence. The same
build's entry 13 supplied the matching caution from the other side:
terminal masking made a *correct* variable look broken and a *broken*
credential look fine. On a clean build, verify file contents by
byte-level reads. Always.

### The executor switch is a milestone responsibility

A milestone's compose carries only that milestone's config (ledger 7),
and the M5-era executor default is applied by a dedicated, idempotent,
hard-failing stage — **§2'** in the m5 install — that re-asserts
`EA_EXECUTOR_DEFAULT=hermes` in the live m2 compose on *every*
invocation, including stage-gated re-runs that skip earlier stages
(ledger 11; findings §4.3). The general rule for builders: **a stage gate
must re-assert the preconditions the skipped stages would have
established**, not merely check that earlier stages once passed. And any
test whose verdict depends on which executor runs asserts that executor
by name — the stub sleeps its TTL and reports success; the real executor
boots in ~1.4 s, hydrates three files, and produces either an artifact or
a failure-shaped report. The two are behaviorally distinct in exactly the
ways the gates check; that is not an accident, it is the assertion.

## 14.4 Secrets staging (the map)

Secrets are never committed, never baked into images, never placed in
compose files. Each is staged at 0600 in a gitignored file on the machine
that consumes it, rotated at every milestone gate:

| Secret | Staged at | Rotation |
|---|---|---|
| registry basic-auth + internal CA | gitignored `.env.registry` / registry VM cert dir | each milestone gate |
| llm-proxy executor / CoS class tokens | executor env file / front-VM `cos.env` | each milestone gate |
| Hindsight write (CoS) / read (executors) | `cos.env` / memory env file | each milestone gate |
| GitHub App key | execution VM, tmpfs, 0600 | revocation-at-reap asserted |
| dashboard publisher HMAC | executor env file | each milestone gate |

The hardening stage closes the loop and is the operator's receipt: trivy
across every deployed image (9/9 clean; pinned-runtime lang-pkg findings
accepted residuals with per-image evidence), an env sweep of every
running container asserting no owner-long-lived token, and the token
lifecycle live — issue → 200 → revoke → (sleep past propagation) → 401.
The amendment to the first build's hygiene: the credential sweep includes
**URL-embedded** credential forms and is byte-level (ledger 5), and a
comment claiming interpolation is itself verified by a byte-level check
that the literal is absent.

## 14.5 Building for coexistence (the rules the builder inherits)

These are the rules that made two organizations live on one estate, and a
new operator on a *clean* estate should keep them anyway — they cost
nothing and they future-proof the second build:

1. **Every compose is born named.** `name: ea-*`, `ea-*` containers, own
   volumes, own ports (the memory API on 8082, the gateway on 8083, the
   manager on 8086 in the reference deployment). Entry 8's takeover cost
   one recovery sequence; the rule costs one line per compose.
2. **Shared-network membership is compose-declared**, never attached by
   hand; services live only on the shared network with aliases declared
   (ledger 2 — and beware dual-network aliasing: Docker's embedded DNS
   fails peer lookups for it).
3. **Publish queue-direct.** The manager publishes to the `ea-tasks`
   queue via the default exchange, routing key = queue name (D-routing).
   On a shared topic exchange, two bridges bound `…#` and deriving the
   same WorkflowId race to first-start — V2 observed its own tasks
   executed by the first build's pipeline live. Queue-direct removes the race at the
   publish point; capability fan-out returns as a versioned additive
   change if ever needed.
4. **Credentials that outlive scripts.** Before minting, check for a
   persistent volume that outlives the script; when one side of a
   volume/env pair changes, align the other and log it (ledger 3).
5. **Restart order after any reboot** (dependency-ordered; with
   `unless-stopped` everywhere this is the manual fallback, not the
   norm): engine + store → broker + bridge → worker + lifecycle →
   dashboards → CoS profile → gateway/manager. Everything else resolves
   names that exist only while their containers run.

## 14.6 The timeline, honestly

Three calendar days, four VMs, coexistence throughout — from the
committed record (`WORKING-STATE.md` seventh–thirteenth updates, findings
§6):

| Day | What happened |
|---|---|
| **2026-11-13** | Declare-start security decisions (§9.1) taken; **S0 chassis applied** — surfaced 4 issues, all fixed and logged same day (ledger 1–4); **S1** registry TLS + bcrypt auth + CA distribution, tests green; **S2** image re-tag 3/3 digest-identical; interim restart-policy flip on live containers (no first-build evidence mutated); **S3** cross-VM publish test green; **S4** transform — the 33-file `ea-`-named deploy tree, plus the wiring review that caught the tracked credential (ledger 5, fixed with a first-build backport) |
| **2026-11-14** | **m0 apply green** (V2-native publish test; 5 gates PASS); **m1** install + T1–T5 + **TP-M1 6/6**; **m2** install, first run failed on the era-mismatch (ledger 7), re-run green + **TP-M2** incl. the no-pull rule; **m3** executors + **TP-M3 7/7** (boot p50 ≈ 1.4 s, coder commit on the demo repo, token lifecycle, zero secrets); **m4** memory + G1–G6 — and the takeover caught and repaired (ledger 8); M5 transform committed |
| **2026-11-15** | **M5**: §1–§3 green; §4 E2E exposed the shared-exchange race → queue-direct fix (ledger 9, 10) and the executor-switch implementation (ledger 11); §5 injections rebuilt for real executors (ledger 12); §6 hardening green incl. the token-check fixes (ledger 13); **TP-M5 signed — the staged build complete** |

The honest pattern in that table: gates failed *openly* on 11-14 and
11-15, each failure was root-caused into the ledger the same day, and the
fix was a rule the next stage enforced. Nothing shipped on hope; nothing
was hidden in a workaround.

## 14.7 The rules for the operator

1. **Inventory first, check-only first, rename micro-gate first.** Never
   let the first real command be a provisioning command, and never let a
   build begin under names it will have to escape later.
2. **Byte-level verification, everywhere.** Configs are proven by parse,
   credentials by scan, commits by `git check-ignore` — display output
   and comments are never evidence.
3. **Era discipline.** A milestone's compose carries only that
   milestone's config; the executor switch is applied by its owning
   stage, hard-failing, on every invocation.
4. **Coexistence names and volumes from birth.** `ea-*` compose, own
   volume, own ports — even on a clean estate where there is nobody to
   collide with yet.
5. **Sign each gate before the next stage opens**, evidence committed
   under the milestone dir. The signature asserts the evidence pack is
   complete; the standing-authorization convention (owner-delegated,
   all-PASS-with-evidence) is recorded in the decision log.

## 14.8 Closing the loop

With the estate standing, the system described in Part II is running
*twice*: the `ea-` organization fully gated and signed, the first organization untouched beside it. The build from scratch is deliberately
unremarkable — eight stages, each check-only'd, applied, gated, and
signed; every failure root-caused into a ledger entry; every rule
committed before it was needed twice. That is the point: **the
organization is provisionable the way software is — from source, beside
its predecessors, with gates — by anyone who can follow the runbook this
chapter narrates.**
