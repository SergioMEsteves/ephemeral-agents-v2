# V2 New-Project Runbook — onboarding another dev-agent team

> **The repeatable recipe:** new project = new VM-Xa-type VM + this recipe
> + the roster. This is the deliverable that turns V2 from a system into a
> platform: each additional project (each dev-agent team) is a bounded,
> checklist-driven onboarding, not a redesign.
>
> Shared infrastructure — the execution VM (rabbitmq, temporal, lifecycle,
> executors), the memory VM (Hindsight), and the registry VM — is
> **project-agnostic**: all teams run on the same spine. What is
> per-project is listed below.

## What is per-project

| Component | Isolation | Why |
|---|---|---|
| VM-Xa (front-of-house) | **one per project** | the CoS, gateway, and manager are the project's boundary; a team's approvals never touch another team's queue path |
| CoS Hermes profile | one per VM-Xa | the project's judgment layer; its kanban board and Hindsight scope are per-project |
| Primary project repo | one per project (default; multi-repo by manifest declaration) | the single source of truth (D4) |
| Hindsight scope | per-project scope key; projects share nothing by default | memory isolation |
| Desktop registry entry | one named remote connection per project | the desktop stays stateless — a team = a named connection |
| Tier-1 tracker (GitHub Issues project) | one per project | plan of record; exporter credential held outside the CoS env |
| GitHub App installation | once per target repo, when coder-style work arrives | 1-minute settings action |
| `max_parallel_agents` (default 5) | manifest-configurable per project | capacity lever per team |

## Onboarding steps (per new project)

1. **Provision VM-Xa(n):** clone the front-of-house VM template
   (stage S0 of `RUNBOOK-V2-BUILD.md`; cloud-init preferred) with a fresh
   static IP from the pool; add to `hosts.env` as `VM_XA2` (etc.) — the
   inventory stays the single source of truth.
2. **Deploy the stack:** gateway + manager images (digest-pinned from the
   registry), ea-net connectivity to the shared execution VM, env from
   the gitignored per-project file. The manager/gateway are stateless —
   no data migration, ever.
3. **Create the project repo** (or register the existing one) and write
   the **project manifest** (`project.yaml`, M1 design §10): repo layout,
   `max_parallel_agents`, TTL defaults, executor defaults, model pinning
   (when the configuration topic closes). The CoS reads it; the manager
   validates `repo_target` against it.
4. **Provision the CoS profile:** the stage-S6 recipe from the build
   runbook — persona from roster `bus-org/chief-of-staff/`, env = exactly
   the four-item allow-list, board initialized, Hindsight scope key =
   project id.
5. **Register the desktop connection:** a named remote gateway connection
   (session-token auth); verify reconnect survives a VM reboot (TP
   assertion 12's check, per project).
6. **Smoke:** one trivial approved task end-to-end on the new project;
   report lands; zero survivors; token revoked.
7. **Record:** decision-log entry (project id, VM, repo, scope key) and
   the team's onboarding date in the V2 issue ledger.

## Capacity notes (multi-team)

- Each project's concurrency is independent (`max_parallel_agents`,
  default 5) but they **share** the execution VM's executor capacity and
  the llm-proxy's aggregate caps — the soak-test gate (§9.3) measures the
  shared ceiling before scaling past ~2 concurrent teams.
- The registry's GC policy (keep-last-3) applies estate-wide; teams share
  image digests (no per-team rebuilds).
- Cross-team isolation today is the VM boundary + per-project Hindsight
  scope + per-project queue consumers; a shared-kernel execution VM means
  the isolation ladder (A → A+ → B → C) applies estate-wide, not per
  team — A+ is the first upgrade if teams multiply or trust diverges.
