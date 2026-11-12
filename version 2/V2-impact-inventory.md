# V2 Build-Phase File-Level Impact Inventory

*Status: DRAFT v1, 2026-11-11. Produced per the owner directive in
`V2-platform-design.md` §9.5: every file required for a full, clean V2 build,
deployment, installation, and all checks — enumerated and mapped to the
decision/finding it serves and to the milestone/gate that exercises it. This
inventory is the artifact the rename micro-gate (§9.7) and every subsequent
gate assert against; gate assertions name the artifact they prove
(platform §7.3), starting here.*

Provenance convention: V2 files derived from a V1 baseline file cite that
file's `deploy/…` path ("carried from V1 baseline"); brand-new V2 files are
marked **new**. V2 deploy-tree paths are written `deploy-v2/…` (the repo
directory name for the V2 deploy layer is not yet fixed in the design docs —
see Gaps); install root on the VMs is `/opt/ea` per
`version 2/ea-rename-mapping.md`. `deploy/` itself is byte-identical V1
evidence and is **not** modified.

Entry columns: **FILE** (V2 path) → **CHANGE/ROLE** → **DECISION/FINDING
SERVED** → **EXERCISED BY**.

---

## 1. Compose files (all milestone stacks) + env var wiring

The `POC_*` → `EA_*` rename surface and network rename `poc-net` → `ea-net`
per platform §1 and `version 2/ea-rename-mapping.md`.

| FILE (V2 path) | CHANGE/ROLE | DECISION/FINDING SERVED | EXERCISED BY |
|---|---|---|---|
| `deploy-v2/m0/rabbitmq/compose.yaml` | carried from V1 baseline `deploy/m0/rabbitmq/compose.yaml`: broker on vm-xb, `5672` (AMQP, cross-VM) + `15672` (mgmt UI, LAN-open per owner 2026-11-08), `RABBITMQ_PASS` from gitignored `.env`; `poc-net` alias → `ea-net`; container `poc-*` → `ea-*` | platform §1 (naming family); §9.1.4 (dashboard compensating control decision at build start — HMAC field vs interface binding) | rename micro-gate (§9.7); V2-M0 gate re-run under `ea` names |
| `deploy-v2/m0/temporal/compose.yaml` | carried from V1 `deploy/m0/temporal/compose.yaml`: Temporal `auto-setup:1.27.0` on `7233` + its own Postgres `postgres:16` (`5432`, `TEMPORAL_DB_PASS` gitignored); network → `ea-net` | platform §1; §7.5 (dependency-ordered restart) | rename micro-gate; V2-M0 gate |
| `deploy-v2/m0/go-sdk-smoke/` (`main.go`, `go.mod`, `go.sum`) | carried from V1 `deploy/m0/go-sdk-smoke/`: Go-for-Temporal language-decision smoke, retargeted `POC_*`→`EA_*`/`ea-net` | platform §1 | V2-M0 gate (chassis) |
| `deploy-v2/m1/compose.yaml` | carried from V1 `deploy/m1/compose.yaml`: topic-bridge (`ea/topic-bridge`), `RABBITMQ_URL` amqp :5672, `TEMPORAL_ADDR temporal:7233`, exchange `agent.tasks`, queue `agent.tasks.durable`, DLQ; `EA_*` envs; `ea-net` | platform §1; §5.3 (topic topology stays one task topic) | rename micro-gate; V2-M1 install gate |
| `deploy-v2/m2/compose.yaml` | carried from V1 `deploy/m2/compose.yaml`: lifecycle (`ea/lifecycle`, `LISTEN :8090`, docker.sock, `EA_TTL_DEFAULT`, `EA_IMAGE_HERMES`/`EA_IMAGE_CODER` digest-pinned refs) + worker (`ea/worker`, `LIFECYCLE_API :8090`, response publisher); env_file `/opt/ea/secrets/m3.env`; `/var/poc/tasks` → `/var/ea/tasks` | platform §1, §9.1.1 (digest-pinned pulls), §9.1.5 (token custody) | rename micro-gate; V2-M2 gate; A+ gate re-verification |
| `deploy-v2/m4/hindsight/compose.yaml` + `initdb.sql` | carried from V1 `deploy/m4/hindsight/*`: pgvector:pg16 + `ea/hindsight-api` `LISTEN :8081`, `EMBEDDINGS=${EMBEDDING_PROVIDER}` (default `none` per platform §4), `HINDSIGHT_DB_PASS`; + **new** token-class auth wiring (read/write token envs) | platform §2 (pointer store on memory VM), §4, §9.1.3 (token split, reach restriction) | V2-M4-equivalent install gate; TP-V2-M1 assertion 6 (env scope); A+ gate (spawn-side hydration re-verification) |
| `deploy-v2/m5/compose.yaml` | carried from V1 `deploy/m5/compose.yaml` + extended: gateway (`ea/gateway`, ports `8080`, `MANAGER_API http://manager:8086`) + manager (`ea/manager`, `RABBITMQ_URL amqp://vm-xb:5672`, roster repo read token, `RESPONSE_QUEUE agent.tasks.response`) + **new** CoS Hermes profile service (resident, `restart: unless-stopped`, §4) with the §5 four-item env allow-list | M1 §1, §4, §5; platform §9.3 (CoS observability — persistent log path/volume) | TP-V2-M1 assertions 2, 6, 7, 9 |
| `deploy-v2/*.env.example` (per-milestone, incl. `ea.env.example` carried from V1 `deploy/m3/m3.env.example`) | carried + extended: every `POC_*` example renamed `EA_*`; **new** vars — registry basic-auth, llm-proxy CoS-class token, Hindsight write/read tokens, CoS gateway session token, exporter tracker credential pointer | platform §9.1 staging note (secrets staged gitignored, 0600, rotation expectation named — vault deferred) | build-start security stage; credential-capability assertion (TP-V2-M1 assertion 6) |
| `deploy-v2/m0/hosts.env.example` → filled `hosts.env` (gitignored) | carried from V1 `deploy/m0/hosts.env.example`: ssh aliases + static IPs for PVE + vm-xa/vm-xb/vm-hindsight | platform §7.10 (inventory-first) | chassis stage `--check-only`; inventory-vs-reality check at minute five |
| `deploy-v2/ea-restart-stack.sh` | carried from V1 `deploy/restart-stack.sh`, ea-named, updated for the V2 stack incl. the CoS profile and the durable llm-proxy mount path | platform §7.5 (reboot survival baked, not documented) | reboot-survival assertions (TP-V2-M1 assertion 7; V2-M5-equivalent) |
| `deploy-v2/check-workstation.sh` | carried from V1 `deploy/check-workstation.sh` unchanged (build workstation tooling) | platform §9.6 (M0-style staged build) | Stage A / chassis stage |
| `deploy-v2/README.md` + per-milestone `install.sh` (m0–m5 equivalents) | carried from V1 `deploy/m*/install.sh` + `deploy/README.md`, rewritten for `/opt/ea` root, `EA_*`, ea images, V2 gates; **new** CoS/install steps at M5-equivalent | platform §9.6 (V1 process, V2 record) | every milestone gate; `--check-only` against committed inventory |

## 2. Go services (`services/` — currently empty; planned V2 files)

Born ea-named per the naming decision; source for the enumeration: M1 §4
(manager changes), §5/§6 (CoS credential + submit path), platform §9.1–9.3.

| FILE (V2 path) | CHANGE/ROLE | DECISION/FINDING SERVED | EXERCISED BY |
|---|---|---|---|
| `services/manager/main.go` (+ env parsing/validation) | carried from V1 manager image source (re-tagged `ea/manager`), **new** in-repo: `priority` field validation (coarse `high|normal|low`, reject out-of-range; log declared value) + pass-through to publish | M1 §4, D8, OQ1 closed; platform §5 (field+consumer same gated change) | TP-V2-M1 assertion 2 |
| `services/manager/approval_hash.go` | **new**: retry-integrity check (same `task_id` ⇒ identical SHA-256 spec hash across retries) + mismatch-reject-and-surface | M1 §4, §7.10; platform §5 | TP-V2-M1 assertion 10 |
| `services/manager/manifest_check.go` | **new** (gated with the manifest milestone): `repo_target` must exist in the project repo's `project.yaml` manifest; deterministic reject | M1 §4, §10 | repo-manifest/manifest-check milestone gate |
| `services/manager/env.go` | carried: env contract (`EA_*`, `RABBITMQ_URL`, `AGENT_LIST_REPO`, `GITHUB_READ_TOKEN`, `RESPONSE_QUEUE`) renamed | platform §1 | rename micro-gate grep |
| `services/lifecycle/main.go` (+ `spawn.go`) | carried from V1 lifecycle, changed: spawn path pulls executor images **by digest** (`ea/hermes-ephemeral@sha256:…`) with digest re-verification at spawn; injects `task_id` as llm-proxy request header (advisory attribution); tmpfs-mounted 0600 GitHub token instead of env where feasible; revocation-at-reap on abnormal exit | platform §9.1.1, §9.1.2, §9.1.5 | build-start security stage; A+ gate re-verification list |
| `services/lifecycle/hydration.go` | carried hydration spawn-env (`HINDSIGHT_URL`, `LLM_WIKI_*`), changed at A+: lifecycle pre-fetches the memory bundle with the executor-class read-only token and mounts it in; degraded-mode rule (Hindsight unreachable ⇒ spawn fails or explicitly-logged degraded) | platform §9.2 (hydration moves spawn-side); M1 §4 | A+ gate (M4_MEMORY_HYDRATE semantics + entrypoint re-verification) |
| `services/worker/main.go` | carried from V1 worker; **new** (build-start choice): publisher-identity/HMAC verification of response-queue messages, or no code change if interface-binding option chosen — decision at build start; if HMAC: additive schema field lands in the same gated change | platform §9.1.4 + change-surface note | V2-M5-equivalent dashboard-control check; schema gate if HMAC chosen |
| `services/hindsight-api/` (`main.go`, `auth.go`) | carried from V1 `poc/hindsight-api` source, changed: token-class auth — CoS write token vs executor read-only token; per-entry writer provenance (task id) recorded | platform §9.1.3 (token split, provenance) | V2-M4-equivalent gate; TP-V2-M1 assertion 6 |
| `services/topic-bridge/`, `services/gateway/` | carried from V1 unchanged in M1 (re-tagged `ea/*`); gateway submit-side logging adequacy is a **build-time verification item** — cited if sufficient, enumerated as a change if not | M1 §6, §4 ("gateway untouched"); platform §9.3 enforcement trail | TP-V2-M1 assertion 9 evidence; board-reconciliation trigger verification |
| `services/contract-tests/` | **new**: reusable contract test suite (spawn-env, message-v1 shapes, catalog/roster shapes) with schema-negative cases (out-of-range priority, manifest-missing `repo_target`, unknown field), built with/ahead of M1 | platform §7.2, §9.6 | TP-V2-M1 prerequisite artifact; replaces V1 per-milestone scripts |
| `services/go.mod` / workspace | **new**: module scaffolding for the Go services tree | platform §9.6 staged build | all services builds |

## 3. Executor entrypoint scripts + Dockerfiles

| FILE (V2 path) | CHANGE/ROLE | DECISION/FINDING SERVED | EXERCISED BY |
|---|---|---|---|
| `deploy-v2/m3/hermes-ephemeral/entrypoint.sh` | carried from V1 `deploy/m3/hermes-ephemeral/entrypoint.sh`, changed: entrypoint guards on every env reference (`set -u` + explicit defaults, lesson §7.9); full hydration contract (persona/wiki/memory) before work; `HINDSIGHT_URL` reach semantics change at A+ (mounted bundle instead of direct :8081 read) | platform §7.9, §9.2; M1 §8 | V2-M3-equivalent gate; A+ gate re-verification list |
| `deploy-v2/m3/claude-coder/entrypoint.sh` | carried from V1 `deploy/m3/claude-coder/entrypoint.sh` (clone → branch → headless run → push → report), token sourced from tmpfs-mounted 0600 file | platform §9.1.5 | V2-M3-equivalent gate; A+ gate |
| `deploy-v2/m3/hermes-ephemeral/Dockerfile`, `deploy-v2/m3/claude-coder/Dockerfile` | carried from V1; images built and re-pushed `ea/hermes-ephemeral`, `ea/claude-coder` **digest-identical** to V1 (rename without rebuild) | platform §1; §9.7.2 (digest equality) | rename micro-gate; registry re-tag check |
| `deploy-v2/m2/executor-stub/{Dockerfile,entrypoint.sh}` | carried from V1 stub (rollback image), `ea/executor-stub`, no-pull pinned-image boot check | platform §7.6 | V2-M2-equivalent deploy gate |
| `deploy-v2/m3/issue-token.sh` → `ea-issue-token.sh` | carried from V1 `deploy/m3/issue-token.sh`: GitHub App JWT → installation token (TTL 1 h), `/opt/poc` → `/opt/ea` paths, revoke-at-reap pairing | M1 §5 (executor credential class); platform §9.1.5 | V2-M3-equivalent gate; zero-survivors/secret-scan gates |
| `deploy-v2/m3/llm-proxy/proxy.js` (+ its compose/launch entry) | carried from V1 `deploy/m3/llm-proxy/proxy.js`, changed: **mounted from a durable host path staged from the repo** (V1 `/tmp` lesson); caller auth — static per-class tokens (executor vs CoS), bind/allow-list restriction, per-token spend/rate caps + logging, per-task `task_id` header (advisory); **bind/allow-list must admit VM-Xa** (CoS cross-VM dependency) | platform §7.1, §9.1.2; third-pass drift pass (CoS→llm-proxy cross-VM) | build-start security stage; endpoint/flow table (§7 below); TP-V2-M1 assertion 5 (model-call failure behavior) |
| `deploy-v2/m3/Dockerfile.services` (equivalent) | carried from V1 `deploy/m2/Dockerfile.services`: one build, two entrypoints (lifecycle/worker split via compose entrypoint override) | platform §9.6 | V2 services stage |

## 4. Queue definitions, registry configuration, lifecycle spawn path

| FILE (V2 path) | CHANGE/ROLE | DECISION/FINDING SERVED | EXERCISED BY |
|---|---|---|---|
| `deploy-v2/m0/install.sh` (broker-topology section) + `deploy-v2/m0/tests/declare-topology-test.sh`, `rmq-stub.py` | carried from V1 `deploy/m0/{install.sh,tests/*}`: topic exchange `agent.tasks`, queues `agent.tasks.durable`/`.dlq`/`.response` — **re-created once under `ea-*` names with the `x-max-priority` argument in the same declaration** (queues don't survive renames; redeclare happens exactly once) | platform §9.7.1 (rename before OQ4 queue work); OQ4 closed; M1 §7 assertion 3 | rename micro-gate estate half; TP-V2-M1 assertion 3 |
| `deploy-v2/registry/` (TLS config — e.g. `nginx.conf`/`config.yml` + internal-CA cert staging note) | **new**: registry VM `:5000` behind TLS (internal CA) + basic auth; credential-distribution story for the basic-auth secret; retention/GC policy (keep-last-N per tag, disk alert) | platform §9.1.1 incl. second-pass sub-gaps | build-start security stage (small gated item) |
| `deploy-v2/m1/install.sh` (publish/registry section) + `deploy-v2/m1/tests/publish.sh` | carried from V1 `deploy/m1/install.sh`, `deploy/m1/tests/publish.sh`: image publish/verify path under `ea/` names, digest-pinned sourcing, no-pull rule | platform §7.6, §9.1.1 | rename micro-gate; V2-M1 install gate |
| `services/lifecycle/spawn.go` | (also listed in §2) the lifecycle spawn path is the enforcement point for digest re-verification, token tmpfs mount, and task_id header injection | platform §9.1.1, §9.1.2, §9.1.5 | A+ gate; build-start security stage |

## 5. Schema + validators

| FILE (V2 path) | CHANGE/ROLE | DECISION/FINDING SERVED | EXERCISED BY |
|---|---|---|---|
| `schemas/message-v1.json` | carried, additive-only edits in gated changes: (a) optional `priority` enum `high|normal|low` with documented default; (b) optional `approval_hash` (SHA-256 over UTF-8 behavioral_spec, whitespace-exact); (c) optional publisher-identity/HMAC field **only if** the in-band dashboard option is chosen at build start; (d) V1-era "POC task message" title corrected at first touch. Breaking changes would trigger message-v2 (none planned) | platform §5 (corrected mechanics: `additionalProperties: false` ⇒ field lands in schema itself, consumers validate current version; field+consumer same gate); M1 D8, §7.10; §9.1.4 | TP-V2-M1 assertions 2, 10; contract-tests negative cases |
| `services/manager/*.go` validators | (§2) consumer-side validation of `priority`, `approval_hash`, `repo_target` — each gated with its schema change | platform §5 | TP-V2-M1 assertions 2, 10 |
| `services/contract-tests/schema/` | **new**: schema-negative fixtures (out-of-range priority, manifest-missing repo_target, unknown field rejection) | platform §9.6 | TP-V2-M1 prerequisite |

## 6. Hosts/env inventory files + committed inventory mapping

| FILE (V2 path) | CHANGE/ROLE | DECISION/FINDING SERVED | EXERCISED BY |
|---|---|---|---|
| `deploy-v2/m0/hosts.env` (gitignored) | carried pattern from V1: ssh aliases + static VM IPs (vm-xa, vm-xb, vm-hindsight, PVE) | platform §7.10 | chassis stage `--check-only` |
| `deploy-v2/*/​.env` (gitignored, 0600) | **new/carried**: RabbitMQ pass, Temporal DB pass, Hindsight DB pass, embeddings config, registry basic-auth, llm-proxy class tokens, Hindsight write/read tokens, CoS session + API tokens, exporter tracker credential — each named in §9.1's staging note with rotation expectation | platform §9.1 staging note | every install gate; secret-scan hard gate (§7.7) |
| `version 2/ea-rename-mapping.md` | carried (committed): the single V1→V2 name mapping table — `poc-net`→`ea-net`, `poc/*`→`ea/*` images, `POC_*`→`EA_*`, `poc-*`→`ea-*` queues/containers, `/opt/poc`→`/opt/ea`; deliberately-unchanged list (poc OS user); estate-half checkbox open | platform §1, §9.7.2 (whitelisted mapping table) | rename micro-gate grep scope; all gate evidence cross-referencing |
| committed chassis inventory (V2 install scripts' inventory stage, e.g. `deploy-v2/m0/inventory.md`) | **new**: VMIDs/IPs pinned in one committed inventory from minute one; `--check-only` dry-run validates against it | platform §7.10 (moving-floor lesson) | chassis stage gate |

## 7. THE ENDPOINT/FLOW TABLE

*The specification the A+ egress allow-list, the credential-capability
assertion (M1 §7.11), and the L2 network analysis all assert against
(platform §9.5). "carried" endpoints are read off the V1 baseline compose
files; auth is stated per endpoint.*

### Component → outbound endpoints

| Component (VM) | Outbound endpoint | Port | Auth | Why |
|---|---|---|---|---|
| **Hermes Desktop (owner workstation)** | VM-Xa gateway (named remote connection in the desktop's gateway registry) | 8080 (LAN HTTP(S)) | per-connection **session token**, generated at VM-Xa setup, stored gitignored both ends | Q1/D3: desktop↔CoS conversational channel; desktop holds no other credential (M1 §3) |
| **CoS profile (VM-Xa)** | own VM-Xa gateway API — submit approved packages; reports endpoint for results/reconcile sweep | 8080 | gateway **API credential** (ordinary client scope) | M1 §5.3, §6.5–6.6; the CoS is a gateway client, nothing more (D11) |
| **CoS profile (VM-Xa)** | **llm-proxy on VM-Xb** (cross-VM) | 9999 (HTTP) | **CoS-class proxy token** (highest-spend actor inside the cap/logging perimeter) | M1 §5.1; platform §9.1.2. **Cross-VM dependency (third-pass drift pass):** front-of-house CoS reasoning degrades when VM-Xb is down — LLM calls fail; proposals stall (error to owner, no partial proposal, per M1 §6 failure table); execution on VM-Xb is equally down. The proxy's **bind/allow-list must admit VM-Xa**. Stated in this table per platform §9.5. |
| **CoS profile (VM-Xa)** | Hindsight on the memory VM (pointer writes after each report lands) | 8081 | **write token** (CoS-only class) | M1 §5.4, §6.6; platform §2, §9.1.3 |
| **CoS profile (VM-Xa)** | external tracker (GitHub Issues by default) — **indirect only**: via the ADR exporter, which holds the tracker credential; the CoS itself holds none | 443 (HTTPS) | none at CoS (credential lives in the exporter) | D12-rev / ADR-0001: master plan tier; credentials stay out of the CoS |
| **Exporter (VM-Xa)** | tracker API (GitHub Issues; ADO/Jira swap-in) | 443 | **tracker token** (gitignored staging per §9.1) | publishes/syncs master-plan status; offline-tolerant (D12-rev) |
| **Gateway (VM-Xa)** | manager API | 8086 (compose-internal) | LAN-internal, no token (POC boundary, carried) | request translation, unchanged in M1 (M1 §4) |
| **Manager (VM-Xa)** | RabbitMQ on VM-Xb (publish validated message-v1) | 5672 | AMQP user/pw (`RABBITMQ_PASS`, gitignored) | M5 compose baseline; D8 — priority reaches broker only as a validated field |
| **Manager (VM-Xa)** | agent-roster git repo | 443 | read-only token (`GITHUB_READ_TOKEN`) | roster catalog reads (carried) |
| **Topic-bridge (VM-Xb)** | RabbitMQ :5672 (consume durable queue, publish to Temporal start); Temporal frontend | 5672 / 7233 | AMQP user/pw; none (Temporal LAN-open, carried) | carried from V1 M1 compose |
| **Worker (VM-Xb)** | Temporal :7233; lifecycle API :8090; RabbitMQ :5672 (response publisher) | 7233 / 8090 / 5672 | Temporal LAN-open; lifecycle network-internal; AMQP user/pw (+ HMAC publisher field if chosen at build start) | carried; platform §9.1.4 |
| **Lifecycle (VM-Xb)** | Docker daemon socket; registry on VM-Xb's registry VM (:5000, digest-pinned pulls + re-verification); GitHub API (token issue/revoke via `ea-issue-token.sh`); Hindsight :8081 at A+ (pre-fetch hydration bundle with read-only token) | docker.sock / 5000 / 443 / 8081 | docker.sock; **registry basic-auth (TLS)**; GitHub App JWT→installation token; **Hindsight read-only token** (new custodianship at A+) | platform §9.1.1, §9.1.5, §9.2 |
| **Executor containers (VM-Xb, on ea-net)** | project repo (github.com, clone/push); **registry :5000** (digest-pinned, no-pull at run time); **llm-proxy :9999** (executor-class token); llm-wiki git shallow-clone; ~~Hindsight :8081~~ (V1: direct read at boot; **A+: removed** — hydration arrives mounted) | 443 / 5000 / 9999 / 443 / (8081→removed) | scoped per-task installation token (tmpfs 0600); registry basic-auth; executor-class proxy token; `LLM_WIKI_READ_TOKEN` (optional, degrades) | V1 hydration contract carried; A+ allow-list = "registry, llm-proxy, github.com only" (platform §9.2) — no broker/Temporal/Postgres/lifecycle/memory-VM reach |
| **Hindsight API (memory VM)** | its own Postgres/pgvector | 5432 (container-internal) | `HINDSIGHT_DB_PASS`; Postgres TLS or container-only bind (§9.1.3) | platform §2 store; M4 baseline carried |
| **Temporal (VM-Xb)** | its Postgres | 5432 (VM-internal) | `TEMPORAL_DB_PASS` | carried |
| **RabbitMQ (VM-Xb)** | — (inbound only: 5672 AMQP, 15672 mgmt UI LAN-open per owner 2026-11-08) | — | AMQP user/pw; mgmt UI operator | carried; §9.1.4 compensating control |
| **Registry VM** | — (inbound only: :5000, now TLS + basic auth, restricted to lifecycle/executor reach) | 5000 | basic-auth (new secret, staged per §9.1) | platform §9.1.1; fallback if TLS blocked: pre-stage images + firewall to lifecycle only |
| **llm-proxy (VM-Xb)** | provider API (openrouter.ai etc.) | 443 | provider key held by the proxy; callers hold only class tokens | platform §9.1.2 one-service-owns-the-provider |

Cross-cutting reach rules this table asserts: executors must NOT reach the
broker (:5672), Temporal/its Postgres (:7233/:5432), the lifecycle (:8090),
or the memory VM (:8081) — the A+ forwarder enforces it; the CoS's broker/
manager-port connection must FAIL (assertion 11, deferred to the A+ gate;
env-negatively asserted at M1 by assertion 6); the dashboard/UI ports
(15672, 8080) stay within the owner's LAN-open decision with the §9.1.4
compensating control.

## 8. Brand-new V2 assets (not derived from a V1 file)

| FILE (V2 path) | CHANGE/ROLE | DECISION/FINDING SERVED | EXERCISED BY |
|---|---|---|---|
| `version 2/cos-profile/` (AGENTS.md/skills, persona wiring for the VM-Xa Hermes profile) | **new**: the CoS as a Hermes profile on the VM-Xa gateway (configuration, not custom code); env contains exactly the §5 four-item allow-list | M1 D3, §3, §5 | TP-V2-M1 assertions 6, 9, 12 |
| `version 2/judgment-corpus/` (10–15 fixtures, Layer 1 machine-checkable + Layer 2 owner-reviewed) | **new**: non-signed pre-gate eval; re-run on CoS persona/roster-context change | M1 §7 (third-pass condition 4) | blocks-or-clears TP-V2-M1 signature |
| exporter (tracker-agnostic; `services/exporter/` or CoS-profile skill — placement at build) | **new**: publishes master plan to external tracker; holds the tracker credential (CoS never does); status flows up | D12-rev; ADR-0001 | TP-V2-M1 assertions 7, 9 |
| board-inspection path definition (in the TP or a small doc, e.g. `version 2/board-inspection.md`) | **new**: direct read of the local board store or a CoS status verb — named at build, not assumed | M1 §7 assertion 9 (third-pass) | TP-V2-M1 assertion 9 |
| `version 2/V2-issue-ledger.md` (or decision-log.md sections) | **new**: every V2 build issue in the V1 format (symptom → wrong assumption → root cause → rule) | platform §9.6 | closing findings report |
| `project.yaml` manifest (lives in each project repo, pattern documented in-repo) | **new**: per-project repos/concurrency-scope config the CoS reads and the manager validates | M1 §10 | repo-manifest/manifest-check milestone gate |
| GitHub-side: `ephemeral-v2-demo` repo | **new**: V2's own demo target (not reusing `ephemeral-poc-demo`) | M1 §9 | first V2 end-to-end run |
| `version 2/V2-impact-inventory.md` (this file) | **new**: the committed §9.5 inventory — the artifact every gate asserts against | platform §9.5 | rename micro-gate; all subsequent gates |
| `version 2/` V2 deploy-tree name decision | see Gaps | — | before first install script |

---

## Gaps not resolvable from the design docs (flagged, not invented)

1. **V2 deploy-tree directory name** — the docs say "the V2 deploy layer is
   born ea-named" and "per-milestone evidence under the V2 deploy tree" but
   never fix the repo directory name; this inventory uses `deploy-v2/` as a
   placeholder. Owner decision needed before the first install script.
2. **Gateway submit-side logging** — M1 §6/platform §9.3 make this a
   build-time verification item (cited if sufficient, enumerated as a change
   if not); whether `services/gateway/` needs a file entry is therefore
   open until that check runs.
3. **Worker dashboard control choice** — HMAC (code + schema field) vs
   interface-binding (no code) is explicitly deferred to build start
   (§9.1.4); both variants are listed above.
4. **Exporter placement** (independent service vs CoS-profile skill) is not
   fixed by D12-rev/ADR-0001; listed at build-time placement.
5. **Registry VM identity** — §9.1.1 puts TLS on "the registry VM's :5000";
   the V1 baseline records the registry host only via `POC_REGISTRY` env and
   the m1 publish test, with no dedicated registry compose file in `deploy/`;
   the V2 registry configuration file is therefore **new** (path provisional).
