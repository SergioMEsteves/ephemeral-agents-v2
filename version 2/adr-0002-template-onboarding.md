# ADR-0002 — Two-template onboarding: VM-Xlg and VM-Xsm

*Status: Accepted (owner, 2026-11-17). Companion to `V2-M1-cos-design.md`
§10 (project manifest), `V2-platform-design.md` §6 (isolation ladder), and
`deploy-v2/RUNBOOK-V2-NEW-PROJECT.md` (the per-project recipe). Written for
senior technical staff; the plain-language treatment belongs to the V2
book's multi-project chapter when that edition is written.*

## Context

Decision D6 (one project = one VM-Xa = one gateway = one CoS = one primary
repo) was written for strong isolation and validated by the V2 build: the
m4 incident proved a same-named compose project IS the project, and the
coexistence rules (born-named composes, own volumes, distinct ports,
distinct queues, queue-direct publishing) are what actually separate two
organizations on one estate. The VM boundary adds a second ring: separate
kernel, separate resource ceiling, separate blast radius.

But D6 does not scale down. Onboarding a small project (a business analyst
with several small workstreams) costs a full VM clone, its own
provisioning pass, and its own slice of the estate for what is often a
1–2-agent workload. The owner asked for a model that keeps the large-project
rule intact without making small projects pay for it.

The platform design already answered the general question: isolation is a
ladder (§6), and the manifest (§10) is the declared per-project
configuration surface. What was missing is a *deployment-shape* decision —
which estate shape a project lands on at onboarding.

## Decision

Two onboarding templates, declared per project at onboarding:

**Template 1 — VM-Xlg (large project).** Today's rule, unchanged: one
project = one VM = one gateway = one CoS = one primary repo. Full
blast-radius isolation, own resource ceiling, own secrets. Onboarding = the
existing 7-step checklist in `RUNBOOK-V2-NEW-PROJECT.md`, unchanged.

**Template 2 — VM-Xsm (small projects).** One VM hosts N small project
stacks, each with its own compose namespace (`ea-<proj>-` prefix), own
gateway port, own CoS container, own queues, own volumes, own repo mount,
own Hindsight scope key. The coexistence rules that let V1 and V2 coexist
apply *within* the VM, per project. This template is a separate milestone —
it is recorded here as the decided shape, but it is **not built** until a
real small-project onboarding demands it (see Consequences).

**Naming:** `Xlg`/`Xsm` are template names, not renames of running VMs.
VM-Xa stays the first Xlg instance and the live front-of-house for the
ephemeral-agents-v2 project; new clones are named `vm-xlg-2`, `vm-xsm-1`,
and so on. The template lives in the PVE template + the provisioning
recipe, not in renaming a running VM.

**Declaration:** the `project.yaml` manifest gains an `isolation_tier`
field (`xlg` | `xsm`), written at onboarding, read by the CoS, validated by
the manager at submit time the same way `repo_target` is. A project can be
promoted from `xsm` to `xlg` later by re-running the same provisioning
recipe against a fresh VM — the tier is a start-state choice, not a lock.

## Consequences

- **What is shared on an Xsm VM, stated honestly:** resource ceilings (one
  noisy project can starve its neighbors) and the secrets surface (project
  credential sets are staged on the same host). This is the coupling the
  Xlg template exists to avoid — acceptable for small projects owned by
  the same person, which is the target case.
- **What is never shared:** compose project names, container names, host
  ports, queues, volumes, Hindsight scope keys. The broker exchange stays
  shared-broker with queue-direct publishing per project queue (ch11's
  rule: the shared exchange is not safe for two first-start-wins
  consumers).
- **Port allocation is a table, not a choice:** the Xsm template ships a
  per-project port table (e.g. project 2 → gateway :8085, CoS :8086;
  project 3 → :8087/:8088), derived from the compose, fixed at onboarding.
- **Hindsight per-project scoping fires here.** The platform design's
  recorded trigger ("per-project Hindsight scoping + per-project
  gateway-token lifecycle triggered at second project", §9.4) is exactly
  what the Xsm template requires; the scope key is the project id in the
  manifest.
- **This ADR also closes review finding M9** (D6 supersedes the recorded
  no-new-VM decision without saying so): D6's supersession is now
  explicit — the no-new-VM decision was a POC-era constraint; the Xlg
  template assumes a new VM per large project, and the Xsm template is the
  small-project alternative. Capacity note: before scaling past ~2
  concurrent teams on the shared execution VM, the §9.3 soak gate
  re-measures the shared ceiling — this applies to Xsm projects the same
  way it applies to Xlg ones.
- **Build order:** the Xsm template is deliberately deferred. When the
  first real small-project onboarding arrives, its milestone is: Xsm
  chassis stage (shared VM, N compose stacks differing only in the project
  token, port table) + the per-project rules above + one e2e smoke per
  project, gate-asserted like every other stage.
