# Pre-build estate checklist — per-VM items before the first build step

> Owner directive (2026-11-11): everything that must be addressed on each
> VM **before** the first step of the V2 build, plus the repo-side items
> that must be green at declare-start. Checked = verified; unchecked =
> done during the build-start session. **No VM item is executed until the
> owner declares the build start** (standing read-only rule).

## VM-Xa — front-of-house (gateway + manager; CoS lands here)

| Item | Why | Source |
|---|---|---|
| Bring-up of reboot-orphaned containers (2026-11-10 cleanup documented them) — `restart-stack.sh <execution-host>` equivalent on Xa or manual `docker compose up -d`; gateway :8080 healthy | build stages assume a running baseline | WORKING-STATE estate note |
| Gateway/manager images re-pointed to `ea/gateway`, `ea/manager` (digest-pinned) at the rename | micro-gate | §9.7 |
| Registry basic-auth + TLS trust (internal CA) staged into the VM's docker config so digest-pinned pulls authenticate | build-start security | §9.1.1 |
| CoS Hermes profile directory created (persona from roster `bus-org/chief-of-staff/`, `restart: unless-stopped`, reboot-safe per book ch14 §14.8) | M1 build stage | M1 §4 |
| CoS profile env = exactly the §5 four-item allow-list; denial list absent (no GitHub token, no queue/manager/registry creds, no ssh keys) | assertion 6 (negative + positive) | M1 §5 |
| CoS-class llm-proxy token + Hindsight WRITE token staged in `cos.env` (0600) | security staging | §9.1.2/9.1.3 |
| Kanban board (Tier 2) initialized for the CoS profile; exporter credential for Tier 1 held outside the CoS env | D12-rev | ADR-0001 |
| Desktop gateway registry entry (named remote connection, session-token auth) prepared on the workstation | OQ1/D3 | M1 §3 |

## VM-Xb — execution (rabbitmq, temporal, worker, bridge, lifecycle, llm-proxy)

| Item | Why | Source |
|---|---|---|
| Bring-up: `bash deploy/restart-stack.sh <execution-host>` (order: engine+store → broker+bridge → worker+lifecycle → dashboards) | orphaned containers from 2026-11-10 cleanup | estate note |
| Registry re-tag step 1 of `deploy/rename-to-ea.sh` run (9 images ea/… digest-verified) | micro-gate | §9.7 |
| Queue re-creation step 2 of `deploy/rename-to-ea.sh`: `ea-tasks` declared **once** with `x-max-priority`; V1 queue drained | micro-gate + OQ4 | §9.7, OQ1/OQ4 |
| Baseline test path step 3 of `deploy/rename-to-ea.sh` re-run green under ea names | micro-gate | §9.7 |
| Registry TLS + basic auth applied (`deploy/security-buildstart/registry/compose.tls.yaml` staged from repo); digest-pinned pull path verified by the lifecycle | build-start security | §9.1.1 |
| Registry GC policy (keep-last-3, 80% disk alert) | unbounded-growth lesson | §9.1.1 |
| llm-proxy v3 verified mounted from durable `/opt/ea/llm-proxy/` (NOT `/tmp` — the V1 lesson); executor + CoS class tokens wired; bind/allow-list admits VM-Xa | lesson 1 + security | §7.1, §9.1.2 |
| Lifecycle spawn path: digest re-verification + task_id attribution header + tmpfs 0600 GitHub App token | build-start security | §9.1.2, §9.1.5 |
| Worker publisher-identity control per owner's build-start choice (HMAC field vs interface binding; default B) | dashboard control | §9.1.4 |
| `restart: unless-stopped` on every service of the Xb stacks | reboot survival baked | §7.5 |

## Memory VM (hindsight API :8081)

| Item | Why | Source |
|---|---|---|
| Token split applied: write token (CoS) vs read-only token (executors) | security | §9.1.3 |
| Proxmox firewall: `:8081` restricted to VM-Xa + VM-Xb | reach restriction | §9.1.3 |
| Postgres TLS or container-only bind; pointer provenance field recorded per entry | security | §9.1.3 |

## Registry VM (private registry :5000)

| Item | Why | Source |
|---|---|---|
| TLS (internal CA) + basic auth (see security-buildstart template) | review critical | §9.1.1 |
| Credential-distribution story: who holds the basic-auth, staged where | staging note | §9.1.1 |
| GC/retention policy active | disk-growth lesson | §9.1.1 |
| `dr-ui` stays removed (2026-11-10 cleanup) | estate hygiene | cleanup record |

## PVE host

| Item | Why | Source |
|---|---|---|
| Proxmox firewall rules for the memory-VM and (A+ later) egress allow-list staged as config, applied only at their gates | isolation ladder | §9.2 |
| Chassis inventory (VMIDs/IPs) re-verified against reality at build start — the committed inventory is the gate's reference | lesson 10 (moving floor) | §7.10 |

## Repo-side declare-start gate (all green now)

- [x] Rename micro-gate repo half (mapping table committed; grep audit clean)
- [x] File-level impact inventory + endpoint table committed (§9.5)
- [x] Judgment corpus runnable (13 fixtures, check.py verified)
- [x] Go services ported ea-named; all 5 modules `go test` green
- [x] M1 manager changes written + tested (priority enum, approval_hash)
- [x] message-v1 schema: `priority` + `approval_hash` added (field+consumer same change)
- [x] Contract test suite green (14/14 checks)
- [x] `deploy/rename-to-ea.sh` staged (syntax-checked; NOT run)
- [x] Security staging templates + secret inventory (placeholders only)
- [ ] Owner declares the build start

## Build-phase deliverable added 2026-11-11 (owner question: "complete enough for a clean build by someone new?")

- **V2 clean-build runbook** — the V2 analog of deploy/README + book ch14:
  owner-inputs checklist (ea-named), the staged-build sequence as operator
  steps, the VM-Xa CoS provisioning recipe (repeatable: new project = new
  VM + recipe + roster), and the desktop↔CoS connection procedure. Done
  when a stranger can rebuild from a bare PVE host using only committed
  files. Written *during* the build as each stage produces its real steps
  (the V2 book remains the closing deliverable; the runbook is its
  operational spine). V1's path (deploy/README + book) is already
  stranger-ready and stays the reference for the V1-proven stages.
