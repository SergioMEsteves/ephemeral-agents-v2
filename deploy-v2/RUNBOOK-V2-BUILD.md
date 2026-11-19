# V2 Clean-Build Runbook — from a bare PVE host to a working V2 estate

> **Audience:** an operator (human or AI-driven) who has cloned this repo
> and wants a clean V2 build. Done-criterion: you can reach a passed
> TP-V2-M1 gate using only committed files. Every step names the script or
> doc section that owns it; failures route there (rule in
> `deploy-v2/README.md` §"When a step fails").
>
> **Status:** drafted 2026-11-11 before the build; steps marked
> ⟂FINALIZE are specified now and get their exact values pinned during
> the build stage that first exercises them (the build is the runbook's
> editor — changes land in the same turn as the stage that ran).
>
> **Naming:** every V2-owned component is `ea-*`-named (see
> `version 2/ea-rename-mapping.md`). The baseline `deploy-v2/m*/` scripts
> carry the estate's pre-rename names until the rename stage below — you
> run them as-is for infrastructure, then the rename re-points everything.

## 0. What you are building

```
desktop (stateless) ──session-token──▶ VM-Xa: CoS Hermes profile + gateway :8080 + manager
                                            │ (approved, validated packages only)
                                            ▼
VM-Xb: rabbitmq (ea-tasks, x-max-priority) · temporal+pg · topic-bridge ·
       lifecycle · worker · llm-proxy · ephemeral executor containers
                                            │
memory VM: hindsight :8081 (write=CoS / read=executors)      registry VM: ea/* images
```

One project = one VM-Xa = one gateway = one CoS = one primary repo.
Per-project replication is `RUNBOOK-V2-NEW-PROJECT.md`.

## 1. Owner inputs — collect ALL before stage 0 (stop and ask if any missing)

| Input | Notes |
|---|---|
| PVE host + 4 static LAN IPs (front-of-house, execution, memory, registry) | one pool; record the name-resolution choice (PVE DNS vs /etc/hosts) in `deploy-v2/m0/decision-log.md` |
| SSH keypair; `poc` user authorized on PVE + all VMs, passwordless sudo | scripts SSH as `poc`, BatchMode only |
| GitHub App (id + private key) | reuse the estate's `ephemeral-agents-poc` App if rebuilding the same org; a brand-new org needs a ~5-minute manual App setup |
| Roster repo (`agent-roster` / `available-agent-list`) + read token | layout contract: the roster repository's own layout doc; example seed in `deploy-v2/m5/agent-list-example/` |
| llm-wiki repo + read token | shallow-cloned by executors at boot |
| Embedding provider key (optional) | omit → zero-vector fallback (reads degenerate but work) |
| TTL/cap values | `EA_TTL_DEFAULT`, team cap |
| Model/provider key for the CoS | staged ONLY as the llm-proxy provider key — the CoS never holds it (M1 §5) |

**Workstation:** docker + buildx, go ≥1.22, `temporal` CLI, `gh` (logged
in), rsync, python3 (+`jsonschema`, `pika` optional). Copy
`deploy-v2/m0/hosts.env.example` → `hosts.env` (gitignored) and fill it —
this file is the single source of truth for VM names/IPs/VMIDs; every
script auto-loads it. **Inventory-first rule:** pin VMIDs/IPs here from
minute one and never let a second copy drift.

## 2. Stage order (each stage: `--check-only` first, then apply, then its gate)

| Stage | What | Run | Gate |
|---|---|---|---|
| **S0 Chassis** | provision 4 VMs on PVE (`qm`), base OS (cloud-init preferred; nbd-mount fallback), netplan, docker on every VM, `poc` user + sudo + docker group, UFW rules, network verification matrix | `bash deploy-v2/m0/install.sh --check-only` → `--apply-netplan` apply | M0 acceptance: matrix green, evidence committed |
| **S1 Registry** | private registry VM: `registry:2`, then TLS + basic auth via `deploy-v2/security-buildstart/registry/compose.tls.yaml` staged from repo; GC policy (keep-last-3, 80% alert); stage registry basic-auth in gitignored `deploy-v2/.env.registry` (0600) | apply compose; `docker login` from every consumer VM | pull + push + auth-negative test |
| **S2 Images** | build/ship the 9 service images ea-named OR re-tag the estate's pre-rename images digest-identically | `bash deploy-v2/rename-to-ea.sh step1` (digest-equality verified per image; hard-fail on mismatch) | 9/9 digest-identical, evidence committed |
| **S3 Broker + engine** | rabbitmq on execution VM; `ea-tasks` queue declared **once** with `x-max-priority` (OQ4 — RabbitMQ cannot add it later); temporal + pg | `deploy-v2/m0/rabbitmq` + `deploy-v2/m0/temporal` compose (ea-named post-rename); step 2 of rename script if re-declaring an existing queue | queue visible with `x-max-priority=3`; cross-VM AMQP publish test |
| **S4 Services** | topic-bridge, lifecycle, worker (compose from the V2 deploy layer; all `restart: unless-stopped`; lifecycle env digest-pinned `EA_IMAGE_*@sha256:…`) | m1 + m2 install flows, ea-named | the estate's baseline M1/M2 test scripts re-run green under ea names (`deploy-v2/rename-to-ea.sh step3`) |
| **S5 Memory** | pgvector + hindsight-api on memory VM; **token split**: `EA_HINDSIGHT_WRITE_TOKEN` (CoS) / read-only `EA_HINDSIGHT_READ_TOKEN` (executors); Proxmox firewall: `:8081` reachable from VM-Xa + VM-Xb only; pointer provenance per entry | m4 flow, ea-named | G1–G6 + write-allowed/read-forbidden token matrix |
| **S6 Front-of-house** | gateway + manager on VM-Xa (`restart: unless-stopped`), ea-named images; then **the CoS profile**: Hermes profile dir on VM-Xa with persona from roster `bus-org/chief-of-staff/`, env = EXACTLY the M1 §5 four-item allow-list (llm-proxy CoS token, gateway session token, gateway API credential, Hindsight write token — nothing else; no GitHub token, no queue/manager/registry creds, no ssh keys); llm-proxy mounted from durable `/opt/ea/llm-proxy/` (never /tmp — the /tmp lesson), bind/allow-list admits VM-Xa; Tier-2 kanban board initialized ⟂FINALIZE (exact profile layout pinned here) | m5 flow + CoS recipe ⟂FINALIZE | manager validation e2e (the M5 acceptance re-run) + credential assertion: env contains exactly the four, negatively asserting the denial list |
| **S7 Desktop + smoke** | desktop → gateway registry connection: on VM-Xa the CoS profile runs as a long-lived `hermes serve` backend bound to the LAN interface (`restart: unless-stopped`; distinct from the pipeline Go gateway :8080); its dashboard session token is staged (§5 credential 2, gitignored 0600). Desktop side (owner): Settings → Gateways → Add connection → Remote gateway → name `vm-xa-cos` → URL `http://<vm-xa>:<hermes-port>` → Session token → Save → **Test** until "Reachable" (tests HTTP + WebSocket legs). Registry auto-redials at startup and on drop (the TP-12 property). Desktop holds ONLY the session token — its own credentials are never inherited by the CoS (M1 §3 link-security rule); contract suite; judgment corpus; one end-to-end: market-analysis example → CoS proposal → owner approval → submission → ephemeral executors → reports → single answer; corrective-info mid-run → follow-on revision package | `python3 deploy-v2/contract-tests/run.py`; `python3 "version 2/judgment-corpus/check.py" … --run <run.json>` | **TP-V2-M1**: assertions 1–12 all PASS (see M1 design §7), corpus Layer-1 at 100%, e2e green, evidence signed |

**Restart order after any reboot** (dependency-ordered; everything is
`restart: unless-stopped` — this is the manual fallback, not the norm):
engine+store → broker+bridge → worker+lifecycle → dashboards → CoS
profile → gateway/manager.

## 3. Secret staging map (vault owner-deferred)

| Secret | Staged at (0600, gitignored) | Rotation |
|---|---|---|
| registry basic-auth + internal CA | `deploy-v2/.env.registry` / registry VM cert dir | each milestone gate |
| llm-proxy executor / CoS class tokens | `deploy-v2/m3/.env` / VM-Xa `cos.env` | each milestone gate |
| Hindsight write (CoS) / read (executors) | `cos.env` / `deploy-v2/m4/.env` | each milestone gate |
| GitHub App key | execution VM `/opt/ea/secrets/app-key.pem` tmpfs 0600 | revocation-at-reap asserted |
| dashboard publisher HMAC (option A) | `deploy-v2/m2/.env` | each milestone gate |

Never in compose files; never in git. `.gitignore` covers `*.env` and `.env.*`.

## 4. Gates and record-keeping

- Every gate names the artifact it proves (lesson 3); a gate fails unless
  report status is success (run-16 lesson).
- Sign each milestone TP **before** starting the next stage; commit
  evidence under the milestone dir (gitignored raw outputs, committed
  summaries per the build convention).
- Run the contract suite at every stage boundary (`deploy-v2/contract-tests/run.py`).
- Keep the V2 issue ledger from day one (§9.6 build process).

## 5. Troubleshooting routing

Standing rule: a failure names its owning section → open that install
doc's Troubleshooting row. Gotchas already fixed in this build:
`/tmp` llm-proxy loss (now durable mount), unguarded `$TASK_PROMPT`
(entrypoint guards, contract-tested), missing `/opt/ea` parent dirs
(declare them before m-installs, as the M4-era lesson taught), queue re-declare
impossible (x-max-priority goes in at S3, once).
