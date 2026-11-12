# Pre-build security staging (platform §9.1) — templates and staged state

> Secrets are staged in **gitignored env files, 0600** while the key vault
> is owner-deferred. This directory holds only templates with placeholders
> — no real value may ever be committed (de-identification standing rule).
> Each controlled item names where its secret is staged and its rotation
> expectation.

## Secret inventory to stage at build start (nothing here exists yet)

| Secret | Class | Staged in (gitignored) | Rotation expectation |
|---|---|---|---|
| Registry basic-auth (user/pass) | estate-wide | `deploy/.env.registry` (0600) | rotate at each milestone gate |
| Registry internal-CA cert + key | estate-wide | `deploy/.env.registry` / cert dir on registry VM (0600) | long-lived internal CA; leaf per year |
| llm-proxy executor-class token | per executor class | `deploy/m3/.env` (0600) | rotate at each milestone gate |
| llm-proxy CoS-class token | CoS only | front-of-house VM `cos.env` (0600, tmpfs-mounted into the profile) | rotate at each milestone gate |
| Hindsight write token (CoS) | CoS only | front-of-house VM `cos.env` (0600) | rotate at each milestone gate |
| Hindsight read token (executors) | executor class | `deploy/m4/.env` (0600) | rotate at each milestone gate |
| Dashboard publisher HMAC key | owner-decided control | `deploy/m2/.env` (0600) | rotate at each milestone gate |

`deploy/.env.*` patterns are already gitignored (verify with
`git check-ignore` before staging anything real).

## 1. Registry transport integrity (review critical — build start)

Target state on the registry VM (`:5000`):
- TLS with an internal-CA cert (server-side auth via basic auth).
- Executor pulls **by digest** (`ea/hermes-ephemeral@sha256:…`) with
  digest re-verification in the lifecycle spawn path.
- Retention/GC: keep-last-3 per tag, disk alert at 80%.
- Credential distribution: registry basic-auth is held by the install
  scripts' env only (`deploy/.env.registry`), never in compose files.

Template: `registry/compose.tls.yaml` (below) is applied at the
build-start security stage, not now.

## 2. llm-proxy caller auth (build start)

- Static per-class tokens: `EA_LLM_PROXY_EXECUTOR_TOKEN`,
  `EA_LLM_PROXY_COS_TOKEN` (distinct values).
- Bind/allow-list: the proxy admits VM-Xa (CoS) + VM-Xb (executors) only.
- Per-token spend/rate cap + per-token usage logging; per-task
  attribution via the lifecycle-injected task_id header (advisory only —
  spoofable by a compromised executor; the enforceable caps key on token
  + container identity, with an aggregate per-token backstop).

## 3. Hindsight token split (build start)

- `EA_HINDSIGHT_WRITE_TOKEN` (CoS-class, write) vs
  `EA_HINDSIGHT_READ_TOKEN` (executor-class, read-only).
- Proxmox firewall: memory VM `:8081` reachable from VM-Xa and VM-Xb only.
- Pointer provenance (writer task id) recorded per entry.

## 4. Dashboard compensating control (owner states choice at build start)

Option A: publisher-identity HMAC (additive message-v1 field + worker
verification — one gated change, field and consumer together).
Option B: bind the dashboards to the owner's workstation interface
(no schema change). **Default if unstated: Option B** (smaller surface).

## 5. GitHub App token custody (rung A)

0600 tmpfs file rather than env where feasible; revocation-at-reap
asserted even when the task ends in failure.
