# Install Inputs Checklist — collect everything BEFORE stage 0

> **Fill this in first.** Every item below is something you must gather,
> create, or decide *before* running the first build step
> (`deploy-v2/RUNBOOK-V2-BUILD.md`, stage S0). The runbook's rule is
> strict: **stop and ask if any input is missing** — an install that
> starts half-staged fails at a gate, and gates are where you want to
> spend your failures, not in a half-built estate.
>
> Each row says: what to gather → where it's used → where it gets staged.
> Nothing here is committed to git; secrets live only in gitignored
> `.env` files on the machines that use them.

## A. Accounts and access

| # | Item | What to do | Used by | Staged at |
|---|---|---|---|---|
| A1 | GitHub account + org you control | The estate installs tokens, clones repos, and pushes task branches under one org | everything GitHub-facing | — |
| A2 | `gh` CLI logged in on the workstation | `gh auth login`; this is the operator's own token, not staged anywhere | runbook steps that read/write repos | workstation keyring |
| A3 | **GitHub App** (id + private key) | Create an App on the org: Contents read+write, ~5-minute setup. Note the App ID and download the private key (.pem) | token issuance for executors (issue → verify → revoke per task) | execution VM `/opt/ea/secrets/app-key.pem`, tmpfs 0600 |
| A4 | App installed on the repos it serves | Install the App on the roster repo, the wiki repo, and the demo/target repo (1-minute action per repo) | per-repo token scoping | GitHub settings |

## B. Network and machines

| # | Item | What to do | Used by | Staged at |
|---|---|---|---|---|
| B1 | PVE host reachable, `qm` available | The chassis stage provisions VMs from it | S0 | — |
| B2 | **4 static LAN IPs** from your pool | One each for: front-of-house (CoS + gateway + manager), execution (broker, engine, workers), memory (Hindsight), registry (image store). Record the VMIDs next to them | every stage | `deploy-v2/m0/hosts.env` (copy from `hosts.env.example`; gitignored) |
| B3 | Name-resolution choice | PVE DNS entries vs `/etc/hosts` on every VM — pick one, record it in `deploy-v2/m0/decision-log.md`, never mix | cross-VM DNS (a dual-network DNS bug is a known ledger entry) | m0 decision-log |
| B4 | SSH keypair + `poc` user | Key authorized on PVE + all VMs; `poc` user with passwordless sudo + docker group. Scripts SSH as `poc`, BatchMode only — no password prompts | every install script | VM `authorized_keys` |
| B5 | Firewall plan | UFW on the VMs; note the ports that will be opened (gateway, CoS backend, registry, broker mgmt) per stage gates | S0/S1/S6 | applied per stage |

## C. Repos and keys the system reads

| # | Item | What to do | Used by | Staged at |
|---|---|---|---|---|
| C1 | **Roster repo** (the agent catalog, e.g. `agent-roster`) | Must exist with its layout contract (persona/skills/tools/constraints files + `index.json`); seed example at `deploy-v2/m5/agent-list-example/` | CoS reads it; executors hydrate persona from it | read token → executor spawn env |
| C2 | **llm-wiki repo** (shared knowledge library) | Must exist (can start nearly empty) | executors shallow-clone at boot | read token → executor spawn env |
| C3 | **Demo/target repo** | The repo coder-style tasks will actually edit; must have the GitHub App installed (A4) | coder executor clone → branch → push | per-task App tokens (auto) |
| C4 | **Model/provider key** (e.g. OpenRouter) | Held by the llm-proxy only — the CoS and executors never hold it directly | llm-proxy signs model calls | `deploy-v2/m3/.env` (executor class) + VM-Xa `cos.env` (CoS class) |
| C5 | Embedding provider key (OPTIONAL) | Omit it → zero-vector fallback; semantic reads degrade but the system works | hindsight-api embedder | memory VM env |

## D. Secrets the install MINTS (do not bring these — they get created during the build)

| # | Item | Minted at | Staged at |
|---|---|---|---|
| D1 | Registry basic-auth (bcrypt) + internal CA | S1 | `deploy-v2/.env.registry` (0600, gitignored) + registry VM cert dir |
| D2 | llm-proxy class tokens (executor / CoS) | S6 staging | `deploy-v2/m3/.env` / VM-Xa `cos.env` (0600) |
| D3 | Hindsight write (CoS) / read (executors) tokens | S5 | `cos.env` / `deploy-v2/m4/.env` |
| D4 | CoS session token (the Desktop's door key) | S6 | VM-Xa env (0600); pasted once into the Desktop connection (book Special 3) |
| D5 | Dashboard publisher control choice | owner decision at build start | `deploy-v2/m2/.env` (HMAC if option A) |

## E. Workstation tooling (build machine, not a VM)

| # | Tool | Why |
|---|---|---|
| E1 | docker + buildx | building/shipping the service images |
| E2 | go ≥ 1.22 | building the Go services |
| E3 | `temporal` CLI | engine health checks in gates |
| E4 | `gh` (logged in, A2) | repo operations |
| E5 | rsync, python3 (+`jsonschema`, `pika`) | file staging; contract test suite |

## F. Configuration values to decide

| # | Value | Default | Where it lands |
|---|---|---|---|
| F1 | Task TTL default | `EA_TTL_DEFAULT` (see m2/m3 env examples) | executor spawn env |
| F2 | Team concurrency cap | 5 (`max_parallel_agents`, manifest-configurable) | project manifest |
| F3 | Registry GC policy | keep-last-3 + 80% disk alert | registry VM |
| F4 | Onboarding template | `xlg` (dedicated VM) or `xsm` (shared small-project VM; chassis deferred — ADR-0002) | `project.yaml` `isolation_tier` |

## Stop conditions — do not start stage 0 until ALL are true

- [ ] A1–A4 done (org, gh login, App created + installed on C1/C2/C3 repos)
- [ ] B1–B5 decided and recorded (4 IPs in `hosts.env`, resolution choice logged, `poc` user works with BatchMode SSH from the workstation to every VM)
- [ ] C1–C4 in hand (roster repo exists with valid layout, wiki repo exists, target repo has the App, model key ready to stage)
- [ ] E1–E5 installed on the workstation
- [ ] F1–F4 decided (defaults are fine; write them down anyway)
- [ ] You have read `deploy-v2/RUNBOOK-V2-BUILD.md` once end to end — the stage table tells you what each gate will demand
- [ ] (Recommended) Proxmox snapshot of the host/VMs immediately before stage 0 — trivial rollback if a stage goes sideways

**Prefer not to type the build yourself?** Install the `ea-install`
skill (`deploy-v2/skills/ea-install/` → your workstation agent's
`~/.hermes/skills/`) and simply ask your Desktop agent to run the
install — it executes this runbook stage by stage and stops at every
gate for your approval. See book **Special 4** for the plain-language
walkthrough.

**Then:** record everything in one file —
`cp deploy-v2/inputs.yaml.example deploy-v2/inputs.yaml`, fill it in
(secrets by PATH only — never values), and validate:

```
python3 deploy-v2/render-inputs.py deploy-v2/inputs.yaml --check    # validate + verify referenced files
python3 deploy-v2/render-inputs.py deploy-v2/inputs.yaml --render   # writes deploy-v2/m0/hosts.env + staging plan
```

The renderer refuses to pass a file with an embedded secret, so this is
also your de-identification check. After a successful `--render`, run
`bash deploy-v2/m0/install.sh --check-only` — the first gate is free and
tells you what the scripts can already see.
