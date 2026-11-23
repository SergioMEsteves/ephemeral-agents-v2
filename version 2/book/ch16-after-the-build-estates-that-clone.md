# Chapter 16 — After the Build: Estates That Clone

> **In plain terms.** A full estate build — four virtual machines, nine
> service images, a broker, a workflow engine, a memory store, credentials —
> took three days the first time. That cost is fine once. It is not fine when
> the point of the system is *starting a new project quickly*: nobody stands
> up an agent team if the standing-up itself takes a long weekend. This
> chapter is about paying the build cost **once**, then freezing the result
> so that every future project starts from a finished estate instead of a
> fresh install. The machine equivalent: you don't rebuild a car for each
> driver — you build the factory line once, and stamp copies.

## 16.1 The three-layer scheme

The estate's virtual machines settle into three layers, each with a
different job (ADR-0002):

| Layer | What it is | What it contains | How long it lives |
|---|---|---|---|
| **Golden base** (`ubuntu-24-ea-base`) | OS-only template | fully updated OS, SSH server, the `poc` user with passwordless sudo, static-IP netplan — *nothing else* (no Docker, no `/opt/ea`, no containers, no secrets, no UFW rules) | permanent; refreshed only deliberately |
| **Built template** (`vm-xlg-built`) | post-build clone | the full ea-named stack: Docker + all nine `ea/*` images baked in, compose trees under `/opt/ea` — **de-identified**: zero minted secrets, zero tokens, zero CA keys, containers stopped | permanent; rebuilt only when the build itself changes |
| **Live estate** | running VMs per project | clone of a built template + freshly minted credentials + this project's config | as long as the project lives; snapshots for rollback |

The separation is the security boundary. The golden base can never leak a
secret — it has none. The built template can never leak one either,
*provided the de-identification step was honest* — which is why that step
is a checklist, not a hope (§16.3).

## 16.2 Why not clone the live estate

The tempting shortcut is: the estate works right now, snapshot it, clone
it, done. Don't. A snapshot of a live estate carries:

- **Minted secrets** — the registry CA and bcrypt hash, broker password,
  Hindsight write/read tokens, the CoS session token, the model key staged
  for the llm-proxy. Every clone would share every credential with every
  other clone. One compromised project VM would hold working keys to all
  of them.
- **Identity residue** — hostname, `/etc/hosts` entries, the CA's
  subject/CN, container names pointed at specific IPs.
- **State** — Temporal history, broker queues, Hindsight rows from the
  previous project. A new project starting on another project's history is
  exactly the kind of quiet contamination the whole architecture exists to
  prevent.

The built template is the live estate **minus everything that makes it
this particular estate** — which is precisely the part worth keeping.

## 16.3 The freeze procedure

After the full stage sequence (Chapter 14) gates green, the build VMs are
frozen in place. The steps, in order:

1. **Zero the minted secrets.** Every credential the build created is
   deleted from its VM: the registry CA and auth env, the broker password
   env, the Hindsight tokens, the CoS session token, the llm-proxy provider
   key. The checklist is the runbook's staging map read backwards — every
   file that §14.4 staged gets removed, and each removal is verified by
   *byte-level read*, not by terminal display (Chapter 12, lesson: display
   masking has faked "the file is gone" before).
2. **Stop the containers.** The stack shuts down cleanly
   (`docker compose down` per stage directory, volumes intact — images and
   compose files are the payload, state is not).
3. **Verify the silence.** A final sweep asserts no token-shaped strings,
   no `.pem` files, no `.env` contents remain on any of the four disks.
   The template conversion is refused until the sweep is clean.
4. **Convert.** Each stopped, de-identified VM becomes a Proxmox template
   (`qm template`). From this moment the disks are read-only gold —
   clones are instant, full copies.
5. **Record it.** ADR-0002 and the runbook get the freeze date, the
   template IDs, and the sweep evidence path, so the next operator knows
   exactly what the template does and does not contain.

## 16.4 Spinning up a project (the ~15-minute path)

A new project needs a four-VM estate. From the built templates:

1. **Clone** — four clones from `vm-xlg-built`, one minute each.
2. **Re-pin** — static IPs and hostnames per the new project's inputs
   (`inputs.yaml` → `render-inputs.py` → `hosts.env`, the same single
   source of truth as every build).
3. **Re-mint** — every credential is generated *fresh on the new estate*:
   registry CA, bcrypt hash, broker password, Hindsight tokens, CoS
   session token, provider key staged from the operator's secret store.
   Nothing is inherited from anywhere.
4. **Bring up** — the compose trees start in dependency order; the gate
   checks from Chapter 14 re-run as the acceptance test.
5. **Register** — the desktop connects to the new estate's gateway with
   its freshly minted session token (Special 4).

Steps 2–5 are the *only* per-project work, and they are the same handful
of commands every time. The measured target — the reason this layer
exists — is a working, isolated, credentialed agent estate in roughly
fifteen minutes instead of days.

## 16.5 The honesty notes

- **The 15-minute claim is a target, not a guarantee.** It was measured on
  the real estate once, end to end; it assumes the clone hosts have the
  images already baked (they do — that is the point of `vm-xlg-built`) and
  that the operator's inputs file is ready. A new GitHub App for a new
  organization still costs its ~5 minutes of manual setup that no
  automation can do (Chapter 14, §14.1).
- **Fast iteration has a second tool.** For rebuild-after-change cycles
  (not new projects), the teardown script wipes the stack in place and
  re-runs `ea-install` — minutes, not hours. Full OS wipes per VM were
  explicitly rejected for this: they cost hours per test cycle and buy
  nothing the template layers don't already give (the decision is recorded
  in the pre-build checklist discussion).
- **The templates age.** OS updates and image rebuilds happen on the live
  side first; the built template is refreshed from a *successful, gated
  build*, never from an ad-hoc fix. The golden base is refreshed the same
  way. A template is a snapshot of a **passed gate**, which is what makes
  it trustworthy.
- **Coexistence carries over.** A new project cloned from the templates
  lands `ea-*` names by default; if it must coexist with a live estate on
  the same broker (Chapter 11), the distinct-queues and distinct-ports
  rules from the build apply unchanged — and if it will *replace* a
  retired estate, reuse of the names is safe because the old one is gone.

## 16.6 Retiring a project — handing the estate to the next one

> **In plain terms.** A project ends — it ships, it pauses, or the team
> moves on. The estate does not. This section is the exit procedure: how
> to *end* a project cleanly and point the same machines at a brand-new
> one, reusing as much of the system as possible. It is the mirror image
> of §16.4: spin-up asks "what does the new project need?"; offboard asks
> "what does the old project still own?"

### 16.6.1 What the old project still owns

When a project ends, it leaves state in exactly seven places. The whole
offboard procedure is: **empty all seven, in this order.**

| # | Where the old project lives | Why it must be cleared |
|---|---|---|
| 1 | **In-flight work** — board cards, queue messages, running workflows | a new project must inherit zero tasks, zero approvals, zero queues |
| 2 | **The CoS's VM-Xa state** — `/opt/ea/cos/state` (board, sessions) and `/opt/ea/repos` (task clones) | this is the project's *memory of itself*; it is disposable by design (Chapter 5) |
| 3 | **Minted credentials** — CoS session token, Hindsight write/read tokens, broker password, registry CA, provider key | every credential was minted *for* this project; none survives the project (§16.4 rule: nothing is inherited) |
| 4 | **The GitHub App installation** on the old project's repo | it grants container-level write to a repo that no longer belongs to this estate |
| 5 | **The Desktop connection** named for the old project | the desktop is stateless (D5), but a stale connection is a door into the wrong estate |
| 6 | **The Tier-1 tracker project** (GitHub Issues) | plan-of-record for the old project; archive it, don't delete it |
| 7 | **Hindsight scope rows** keyed to the old project's scope key | memory isolation is per-project; the next project starts with an empty scope (see the honesty note on scoping) |

The project's *work* — commits, reports, artifacts — needs nothing: it
lives in the git repo and `/opt/ea/reports`, both already outside the
estate's identity. The source of truth moves with the repo, never with
the machines (D4).

### 16.6.2 The two exit paths

Choose by how much changes. **The decision rule: if the old project's
repo, roster, and topology stay the same and only the *work* changes,
take Path A; if the estate points at a different repo (the usual
"brand-new project" case), take Path B.**

**Path A — CoS reset (same estate, same repo, fresh start).** The
lightweight path, ~10 minutes. Everything below the front-of-house
survives: broker, Temporal, lifecycle, executors, registry, Hindsight
VM, images.

1. Wait for or cancel in-flight work; verify the worker queue drains and
   survivors are zero (the reaper's normal close-out).
2. `docker compose down` the m5 front-of-house stack on VM-Xa — the CoS
   container is disposable: profile and roster are read-only mounts,
   so removing it destroys nothing authored.
3. Clear the state volumes: empty `/opt/ea/cos/state` and
   `/opt/ea/repos` on VM-Xa. *This is the step a plain container-delete
   misses* — the container is stateless, but its mounts remember.
4. Remint the CoS session token; re-register the Desktop connection
   (a fresh named entry, fresh token — never reuse the old one).
5. Board and tracker: archive what the audit trail needs (the board's
   backup rule), then start the new backlog.

**Path B — estate reclone (different repo, full identity reset).** The
thorough path, and the one to default to when the new project is
genuinely new. It reuses **everything frozen** and re-mints only what
the project defines.

1. Do Path A's steps 1–2 first (drain in-flight work; bring the
   front-of-house down).
2. **Export the close-out record** before anything is wiped: the final
   TP/evidence packs, the issue ledger, and the decision-log are
   committed in the project repo — that *is* the archive; verify the
   repo is fully pushed before touching any VM.
3. Reclone the four VMs from the built template (`vm-xlg-built`, or the
   golden base `ubuntu-24-ea-base` if the build itself changed) and run
   §16.4's spin-up against the new project's `inputs.yaml`: fresh IPs or
   re-pinned same IPs, fresh credentials, fresh compose bring-up, gates
   re-run as the acceptance test.
4. Register the new project: repo, manifest, roster persona, Desktop
   connection, GitHub App installation on the new repo, new tracker
   project, new Hindsight scope key.
5. Record the offboard in the decision log (retired project id, date,
   archive location) and the onboarding per the new-project runbook.

Both paths end identically: **the new project starts with an estate
that carries nothing from the old one** — no queues, no tokens, no
memory, no board — which is the same guarantee a from-scratch build
gives, at template speed.

### 16.6.3 The honesty notes

- **No offboard script exists yet.** Paths A and B are checklists, not
  automation (`deploy-v2/RUNBOOK-V2-OFFBOARD.md` is the executable
  checklist). Every ingredient is individually proven — the profile
  restage is the same one `m1-cos/install.sh` performs, the token mint
  is the same §6 path — but the composed procedure has not been run by
  a newcomer, so treat it like a first-build: verify each step's
  expected result, don't run ahead.
- **The built template is the multiplier.** Without it, Path B costs a
  full rebuild (days). With it, minutes. The freeze procedure (§16.3)
  is therefore not an optimization — it is what makes offboarding
  cheap. If `vm-xlg-built` has not been frozen yet, the honest Path B
  is: freeze first, then reclone.
- **Hindsight scoping is per-key, enforced thin.** Memory isolation
  today is a scope-key convention, not a hard boundary (a known
  deferred item). On Path A, explicitly delete the old project's scope
  rows on the memory VM; on Path B the reclone starts the store empty.
- **The desktop never carries project state, so there is nothing to
  clean there** — but delete the old *connection* anyway: a stale
  named connection pointing at a dead estate is how operators end up
  talking to the wrong CoS.
- **Secrets never survive, ever.** The re-mint rule (§16.4) is not
  relaxed at offboard: a credential minted for project N must never
  authenticate project N+1, even when "N+1" is the same humans on the
  same machines.

## 16.7 The one-line summary

**Build once, gate it, strip it, freeze it.** Every project after the
first one is a clone plus a re-mint — and when a project ends, the
estate empties its seven pockets and starts the next one clean. The
factory line pays for itself from the second car on, and it never
carries the previous car's passengers.

---

*This chapter describes the committed freeze/spin-up procedure
(ADR-0002, the V2 runbook's post-build section, and the golden-template
decision of 2026-11-20). The `ubuntu-24-ea-base` golden template exists in
the estate today; the `vm-xlg-built` conversion follows it and carries the
same gate rule: a template is minted only from a build whose gates all
passed, with the sweep evidence on file. As everywhere in this book, host
addresses are placeholders; credentials live only in gitignored env files
on the machines that need them.*
