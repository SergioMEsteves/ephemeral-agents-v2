# deploy-v2/ — the V2 deploy layer

One tree: everything needed to install, run, and verify the V2 (Second
Edition) estate from a bare PVE host. Nothing in this tree depends on any
other deploy tree.

## Layout

- `m0/` — chassis stage: host provisioning, netplan, docker, UFW, name
  resolution (`install.sh`, `vm-sizing.sh`, `hosts.env.example`,
  `rabbitmq/`, `temporal/`, `go-sdk-smoke/`, `tests/`, `decision-log.md`,
  `evidence/`).
- `m1/` — topic-bridge image and compose, publish/verify flow (`install.sh`,
  `Dockerfile`, `compose.yaml`, `tests/`, `evidence/`).
- `m1-cos/` — CoS Hermes profile service (resident, `restart: unless-stopped`).
- `m2/` — lifecycle + worker services (`install.sh`, `compose.yaml`,
  `compose.m3-era.yaml`, `Dockerfile.services`, `executor-stub/`, `tests/`,
  `evidence/`).
- `m3/` — executor images and tokens (`hermes-ephemeral/`, `claude-coder/`,
  `issue-token.sh`, `llm-proxy/`, `m3.env.example`, `install.sh`,
  `concurrency-decision.md`, `evidence/`).
- `m4/` — hindsight memory stack (`hindsight/` compose + initdb, `install.sh`,
  `evidence/`).
- `m5/` — gateway + manager + CoS profile compose, agent list example,
  end-to-end deploy (`compose.yaml`, `install.sh`, `e2e-deploy.sh`,
  `Dockerfile`, `set-executor-default.py`, `report-contract.md`,
  `agent-list-example/`, `decision-log.md`, `evidence/`).

## Top-level deliverables

- `RUNBOOK-V2-BUILD.md` — the clean-build runbook: bare PVE host → passed
  TP-V2-M1 gate, stage by stage (S0–S7), each step naming its script or doc.
- `RUNBOOK-V2-NEW-PROJECT.md` — the per-project replication recipe for
  adopting teams.
- `PREBUILD-CHECKLIST.md` — per-VM pre-build checklist (VM-Xa, VM-Xb, memory
  VM, registry VM, PVE host) with source decisions.
- `contract-tests/` — the reusable contract test suite (`run.py`): message-v1,
  catalog shape, spawn-env entrypoint guards. Run at every stage boundary.
- `rename-to-ea.sh` — the `ea-` naming script: re-tag images by digest,
  declare `ea-tasks` with `x-max-priority`, baseline test path under ea names.
- `security-buildstart/` — secret inventory and rotation expectations,
  registry TLS/basic-auth compose template, build-start security staging.
- `restart-stack.sh` — post-reboot bring-up of the stack in dependency order
  (`bash restart-stack.sh <execution-host>`).
- `check-workstation.sh` — verify the build workstation (docker, go, temporal
  CLI, gh, rsync, SSH auth) before running `m0/install.sh`.

## Conventions

- Secrets are never committed: per-milestone `*.env.example` files document
  the variables; real values live in gitignored env files (0600) staged at
  deploy time (`.env.registry` for the registry, milestone `.env` files).
- Composes parameterize every credential (`${VAR:?set VAR in .env}`); no
  literal secrets in tracked files.
- Every milestone gate signs its evidence into `m*/evidence/`; decision
  records live in `m*/decision-log.md` (and the root `decision-log.md`).
- Container/network/image names use the `ea-` family (`ea-net`, `ea/…`
  images, `ea-*` containers and queues); paths on the estate root at
  `/opt/ea/`.

## When a step fails

Each runbook stage names the script or doc section that owns it — failures
route there. If a milestone install fails, re-run it: every `install.sh` is
idempotent (safe to re-run against a partially configured host). For
post-reboot orphans, `restart-stack.sh` brings the stack back in dependency
order.
