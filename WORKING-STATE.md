# WORKING-STATE.md — ephemeral-agents-v2 session bootstrap

> **Read this first in every new session.** This file is the living continuity
> record: current state, decisions, open questions, next actions. Update it in
> the same turn a decision is made or a step completes. Context lives HERE
> (cheap, read once) — not in the conversation (expensive, resent every turn).

*Last updated: 2026-11-13 (sixth) — S4 OPEN. deploy-v2 transform
COMPLETE: 33-file tree ea-named end-to-end (paths repointed to
`deploy-v2/mN`, broker user `ea:`, ea-tasks queue family, ea labels,
`ea/executor-stub`, demo repo `ephemeral-v2-demo`). Coexistence
amendments: m0 §3/§4 reuse live V1 broker/Temporal when present;
§1 no longer renames hostnames on already-provisioned VMs
(`vm-hermes-agent`/`vm-ephemeral-agents` kept). m0 Tier-1 harness
9/9 PASS (stub now records PUTs; `5 declares + 1 probe` assertions).
services/ response-queue sync to `ea-tasks.response` — all 5 modules
build+test green. Ready to commit, then staged build stages 1–2.)*

*Prior: 2026-11-13 (fifth) — S4 OPEN. Owner chose `deploy-v2/` as the
V2 deploy-tree name. Tree created (33 files, ea-named); broker wiring
done (`ea` user + permissions, `ea-tasks.dlq` declared,
`agent.tasks.#` binding verified on the live broker). Credential sweep
miss found during the S4 wiring review and fixed: the tracked
`deploy/m1|2/m5` composes carried a literal 16-char broker password in
`RABBITMQ_URL` (stale V1-era value — does NOT match the live broker
password; live value only in gitignored .env) — now parameterized
`${RABBITMQ_PASS:?set RABBITMQ_PASS in .env}` in V2 (`0734c57`), V1
backport `c2649a7`; deploy-v2 copies hardened (`5deb77c` + ledger
entry 5). Verified byte-level: zero credential bytes remain in either
repo's tracked files.)*

*Prior: 2026-11-13 — BUILD PHASE DECLARED OPEN (owner, this
session). Rename estate half steps 1–2 EXECUTED: registry re-tag
3/3 digest-identical (correction: only 3 V1 images were ever
registry-resident — the other 6 of the listed 9 were built at install
time, never pushed; `rename-to-ea.sh` IMAGES list corrected), stale
`agent.tasks.dlq` (35 msgs) deleted, `ea-tasks` declared durable with
`x-max-priority: 3` (the single OQ4 declaration point). V1
`agent.tasks.*` queues untouched pending switch-over. Step 3 (baseline
path under ea names) defers to staged-build stages 1–2. Registry VM
recovered: it was up but had shifted address after downtime (DHCP
lease move — pinned-static item now a build-start security item);
drive-cycled once. HEAD pushed after rename-estate commit.)*

*Addendum (same day, `d214a4b`): final gap analysis
(`version 2/V2-gap-analysis.md` — 20 gaps, all enumerated/classified/
owned, none unknown) and feasibility study
(`version 2/V2-feasibility-study.md` — FR-1..9 + NFR-1..9 each evidenced;
verdict feasible/useful/successful, recommends build start). Design-side
record now complete; the declare-start gate stands.*

## Current position

- **V2 build phase: OPEN.** Repo-side half of the `ea-` rename micro-gate
  done (2026-11-11, `d2afc5d`): mapping table at
  `version 2/ea-rename-mapping.md`; grep audit over V2-owned trees clean
  (V2 deploy layer will be born `ea-`-named; baseline `deploy/` keeps V1
  names per §1 of the platform design). Estate half is separately gated
  and pending owner go-ahead: registry re-tag of the 9 images under
  `ea/…` (digest equality), queue re-create under `ea-*` with the single
  `x-max-priority` declaration, baseline test path re-run green under
  `ea` names. Then: file-level impact inventory + endpoint table
  (§9.5) → build-start security items (§9.1) → staged build → M1.

- **V1** (`github.com/arvisdev/ephemeral-agents`, public, FROZEN): complete
  POC record — M0–M5 signed, book (15 chapters), findings report,
  retrospective. Baseline cited by hash; see README. Read-only except bug
  fixes / doc corrections / security patches (backport convention: fix in V2
  first, `V1 backport:` commit to V1).
- **V2** (this repo, private, LIVE): synced baseline from V1 @ `4de7a06…`
  (book, deploy layer, schemas, license set — byte-identical). Ready to begin.
- **Estate** (version-agnostic hardware, healthy as of 2026-11-08):
  - front-of-house VM: gateway (:8080) + manager only — deterministic Go, no
    agent (deliberate V1 boundary)
  - execution VM: rabbitmq, temporal+pg, temporal-ui (:8080), broker mgmt UI
    (:15672, LAN-open by owner decision 2026-11-08), worker, bridge,
    lifecycle, llm-proxy (v3, mounts from /opt/poc/llm-proxy/)
  - memory VM: hindsight API :8081; registry VM: private registry :5000
  - post-reboot bring-up: `bash deploy/restart-stack.sh <execution-host>`
  - **2026-11-13 (second) — S0 CHASSIS EXECUTED + fixed.** Owner §9.1
  decisions at build start: dashboard control = interface binding
  (no schema touch); registry transport = TLS + basic-auth primary;
  coexistence = preserve V1 credentials (broker pass reused, temporal
  aligned via socket-auth ALTER USER to the fresh V2 pass). S0 apply
  surfaced 4 issues, all fixed and logged in the new
  `version 2/V2-issue-ledger.md` (netplan network-root bug; temporal
  compose-declared on poc-net ONLY — rabbitmq-pattern, dual-network DNS
  SERVFAIL; credential-regen vs persistent volume; registry VM DHCP
  drift). Temporal healthy on poc-net, worker registered on poc-tasks,
  bridge consuming, DLQ drained (3 benign `m0-cross-test` smoke
  publishes the bridge rightly rejected). Registry VM: `vm-registry`
  ssh alias added; static netplan pin needs ONE owner-run command (its
  user lacks passwordless sudo) — S0 close-out = first reboot-and-reach.
  S0 evidence: WORKING-STATE shows HEAD `9ad275f`+S0-notes. Next: S1
  registry TLS + basic-auth (compose.tls.yaml, .env.registry, GC
  keep-last-N), then S2 images (rename step1 already green 3/3), S3+.
- **2026-11-13 (fourth) — S2/S3 CLOSED.** S2 gate green: 3/3 ea-images
  digest-identical to their poc sources (re-verified from manifest
  headers); the other 6 images are install-built by the V2 deploy layer
  (never registry-resident in V1 — nothing to re-tag). Interim
  restart-policy flip done via `docker update --restart unless-stopped`
  on all 8 live containers across vm-xb + memory VM (no V1 evidence
  files mutated); the V2 layer bakes it in compose. S3 gate green:
  cross-VM AMQP publish test — publish from vm-xa (the manager path)
  over :5672/15672 to `ea-tasks` returned routed:true, message landed
  (queue depth 1), fetched+acked with correct payload. Note: the
  rabbitmq management API's queue-depth stats lag briefly after a
  publish — rabbitmqctl is authoritative. **Open owner decision before
  S4:** the V2 deploy-tree directory name (the docs say "born
  ea-named"; the impact inventory used `deploy-v2/` as a placeholder —
  owner decides the real name before the first S4 install script).
- **2026-11-13 (third) — S1 EXECUTED + verified.** Registry VM: TLS
  (internal CA, leaf cert IP-SAN 192.0.2.13) + bcrypt htpasswd
  (passlib; registry v3.1.2 requires bcrypt — the passlib default
  $apr1$ scheme was rejected) + REGISTRY_HTTP_TLS_CERTIFICATE (v3 env
  var name — the v2-style CERT name is silently ignored) + delete
  enabled. Registry data preserved (existing bind ./data, 2.2G).
  Consumers: CA cert distributed + docker login verified on vm-xa,
  vm-xb, vm-hindsight. Workstation: docker daemon still needs one
  owner sudo command for /etc/docker/certs.d, but the workstation is
  fully validated via the rootless podman context (CA in
  ~/.config/containers/certs.d/192.0.2.13:5000/ — no sudo): login,
  pull, push, delete all green (podman rejects underscore-leading
  repo names where docker accepted them — noted). Tests green: pull with creds (200), auth-negative
  (401), push+delete (202, test-s1 image deleted), plain HTTP 400.
  Registry UI: joxit via nginx proxy_pass to https://registry:5000
  with fixed basic-auth header (NGINX_PROXY_HEADER_Authorization) —
  catalog 200 through the proxy, UI page 200 from the workstation.
  GC: weekly cron (Mon 03:00) running registry garbage-collect against
  /etc/distribution/config.yml (v3 path) + disk alert at 80% (current
  45%). Repo template corrected to match reality (CERTIFICATE env var
  name, ./data bind path, pinned storage root). Next: S2 images, S3+.
- **2026-11-13 estate recovery + pre-start sweep (owner-requested fix):**
    ran `deploy/restart-stack.sh vm-xb` — temporal+pg back up (healthy),
    worker registered on `poc-tasks`, bridge consuming, dashboards 200;
    root cause: the temporal stack (V1-era, `restart: no`) never came back
    after the host reboot and its first auto-start raced its own DB (one
    manual `docker start` cleared it). Memory VM: hindsight-pg had the
    same orphan (exited 255, 38 h) — brought up, healthy, `/healthz` 200.
    Registry VM verified (API 200). Residuals noted: temporal stack still
    `restart: no` (V2 build bakes `unless-stopped` — interim flip offered);
    `agent.tasks.dlq` holds 35 stale V1 messages (drained at rename
    step 2); no ssh alias exists for the registry VM (IP-only access);
    chassis inventory re-verify, registry TLS/auth, secret staging, and
    the desktop registry entry remain the open declare-start items.
    gh auth verified (`arvisdev`). Desktop-gateway-connection setup was
    started early at owner request and **parked at owner direction
    (2026-11-13)** until the build completes: the desktop side needs a
    running `hermes serve` CoS backend on VM-Xa (built at stage S7), so
    the connection is created then — procedure already pinned in the S7
    runbook row (`9712193`, from the official multi-connection-desktop
    docs).
    (order: engine+store → broker+bridge → worker+lifecycle → dashboards)

## Active milestone — V2-M1: the Chief-of-Staff agent

Persistent resident Hermes agent with the bus-org chief-of-staff persona on
the front-of-house VM, between the unchanged gateway and manager. **The agent
proposes, the code disposes** — the manager validates every proposal.

### Decided (2026-11-07/08)

1. Pipeline: desktop → gateway (unchanged) → CoS (new) → manager (unchanged,
   still validates) → queue → ephemeral executor → report
2. Persistent resident agent, NOT the ephemeral `eph-chief-of-staff` worker
   (that roster entry stays for principals needing coordination artifacts)
3. No new VM, no new credentials class — CoS submits through the gateway API
4. CoS hydrates like eph-workers do: persona files, llm-wiki, Hindsight —
   the hydration contract gains its first persistent consumer
5. V1 stays frozen; this milestone lives only here; its own TP + gates
   required before it counts (gate rule carried forward from V1)

### Open questions

- **Q1 — desktop↔CoS connection:** REVISED 2026-11-09 → native Hermes
  Desktop gateway registry (named remote connections, session-token auth);
  the bespoke HTTP API of the morning draft is rejected.
- **Q2 — approval mode:** ANSWERED 2026-11-09 → ask-before-submit.
- **2026-11-09 design-v2 decisions D3–D11** (runtime shape, repo as source
   of truth, desktop stateless, one CoS per project VM, management model,
   priority field, parallelism, change management) — recorded in
   `version 2/V2-M1-cos-design.md`; plus OQ1–OQ4 there.
- **2026-11-09 (second):** harness set stays at two (claude-code + hermes;
   third-harness criteria in design §8); VM-Xb carries over unchanged for
   the V2 test run (design §9); V2 gets its own demo repo. Model
   specification & configurables = deferred topic.
- **2026-11-09 (third):** single-repo-per-project default convention with
   per-project manifest (design §10); multi-flow concurrency resolved —
   worktrees rejected, M1 sequential same-repo, later scope-declaration
   milestone (design §11). Deferred topics queued: model specification &
   configurables, secure key management.
- **2026-11-09 (fourth):** 9-item open-items queue adopted, worked
   one-by-one: (1) model spec & configurables — OPENED AND RESET at owner
   direction, restarts from scratch later; (2) secure key management —
   deferred; (3) isolation level; (4) embeddings provider; (5) wiki
   curation automation; (6) dependency refresh policy; (7) umbrella
   compose; (8) contract test suite; (9) production hardening.
- **2026-11-10 platform decisions (owner), recorded in
  `version 2/V2-platform-design.md` (DRAFT v1):**
  (a) **`ea-` naming family** replaces all V1 "poc" names (`ea-net`,
  `ea/hermes-ephemeral`, `ea/claude-coder`, `EA_*` envs) — decided now,
  executed as the opening action of the V2 build phase; baseline
  `deploy/` keeps V1 names until then; docs reference only V2 names
  after the rename. (b) **Memory pointer-store convention:** documents
  live only in the project repo; Hindsight stores pointers only; CoS
  writes, memory VM stores, repo is content. (c) **Concurrency default
  5** ephemeral agents in flight, manifest-configurable
  (`max_parallel_agents`); M1 same-repo sequential (design §11).
  (d) **Embeddings:** evidence-driven — zero-vector fallback for M1;
  small self-hosted model on the memory VM only if pointer recall
  proves poor. (e) **Queue policy:** message-v1 additive-only evolution;
  breaking change ⇒ versioned message-v2; new message types as gated
  additions. (f) **Isolation ladder:** A (containers) for M1; A+
  (rootless runtime + egress allow-list) as a separately-gated change
  right after M1's gate; B (gVisor) / C (micro-VM) trigger-gated.
  (g) **V1 lessons pre-applied** in the V2 build, lesson→build-step
  mapped (platform-design §7). Queue items 3 and 4 are thereby resolved
  as policy; item 3's A+ implementation is a post-M1 build milestone.
- **2026-11-10 (second): END-TO-END DESIGN REVIEW performed and findings
  ACCEPTED (owner).** 28 findings (4 critical / 10 major / 9 minor /
  5 observation), verdict **approve with conditions**. Applied in the
  docs: schema-evolution mechanics corrected (platform §5); CoS state
  persistence specified as `cos-state/state.json` in the project repo
  per-transition (M1 §6.8); failure behaviors completed (M1 §6); gate
  assertions 9–12 added (no-submit-without-approval, approval-payload
  hash pinning, credential capability check, desktop reconnect) + the
  judgment corpus as a non-signed pre-gate eval (M1 §7); registry
  TLS+digest pinning, llm-proxy/Hindsight auth, dashboard publisher
  control, token custody pulled forward as build-start controls
  (platform §9.1); A+ re-specified as segmentation + rootless, both
  gate-asserted (§9.2); capacity model + soak test (§9.3); CoS
  observability minimum (§9.3); D6 supersedes the 2026-11-08 "no new VM"
  note for multi-project growth (§9.4); rename-before-OQ4 ordering +
  rename micro-gate (§9.7). New build-phase commitments (owner
  directive): **file-level impact inventory** before the first milestone
  (§9.5) and the **full V1-style build process with a V2 issue ledger**
  (§9.6). **V2 book timing decided (owner):** the V2 book is written
  after the full installation/deployment is proven working — the closing
  deliverable, containing V2's findings and corrective actions from the
  record. **Second-pass review performed (2026-11-10, third): verdict
  ready-with-conditions; report persisted at `version 2/V2-design-review-report.md`.**
  Convergent critical: the cos-state/state.json mechanism (M1 §6.8)
  contradicts the §5 CoS credential contract (no GitHub token) — owner
  decision required: scoped CoS repo credential (amend §5) OR local
  volume + Hindsight pointer (amend §6.8). Plus: approval-hash verifier
  must be named (manager; enumerated gated change), assertion 11 marked
  conditional to A+, assertion 2 OQ4-conditional, A+ memory-hydration +
  Hindsight token-split decisions recorded, doc drift fixed. Next gate:
  owner rules on the credential question + conditions applied, then the
  build phase opens with the rename + inventory.
- **2026-11-10 (fourth):** V2 feature list created — `version 2/V2-feature-list.md`
  (DRAFT v1): the full V2 offer as a status-marked feature inventory
  (decided / trigger-gated / deferred) across intake, pipeline, work
  management, memory, security/isolation, operations, and documentation,
  closing with the one-line offer.
- **2026-11-10 (fourth): D12 ADOPTED (owner) — kanban board as the CoS
  work board.** One board per project CoS; card = work package; columns
  proposed → approved → submitted → in-flight → reported → rolled up;
  report events move cards. **Desk, never the door:** queue is the only
  execution truth; cards reach "submitted" only via the approval flow
  (gate-asserted, TP 9 amended). **Resolves the second-pass review's
  condition 1 (critical):** the board replaces `cos-state/state.json` as
  the CoS state store of record — lives on VM-Xa with the profile,
  reboot-durable, no GitHub credential needed; repo stays source of
  truth for project content. Board history = submit-side audit trail;
  desktop board visibility = build-time verification item. Remaining
  review conditions: (2) reconcile assertions 2/3/10/11 (name the
  approval-hash verifier, mark 11 conditional to A+), (3) record A+
  memory-hydration + Hindsight token-split choices, (4) doc drift.
- **2026-11-10 (fifth): THIRD-PASS REVIEW performed** (report updated in
  `version 2/V2-design-review-report.md`). D12 confirmed correct by both
  panels; verdict **ready-with-conditions (narrowing)**. Five conditions
  before the build gate: (1) restate §5's credential allow-list (the CoS
  now holds a Hindsight write token + llm-proxy CoS-class token —
  "exactly three credentials" is stale and a conforming build would fail
  assertion 6); (2) fix the approval-hash mechanism (message-v1 hash
  field; M1 manager check = retry integrity + mismatch-reject; §7.10
  reworded to tamper-evidence — a message-carried hash cannot prevent
  mutation; canonicalization defined; gateway-side approval registration
  = later enforcement change); (3) board durability contract (storage as
  build-time verification item, backup/export, fail-safe-to-no-submit on
  unreadable/ambiguous state, write-ahead ordering, corruption case in
  TP 7); (4) make the judgment corpus runnable (fixtures, location,
  machine-checkable fields, threshold — carried through both passes);
  (5) drift pass (audit-trail provenance: board = intent trail,
  gateway/manager log = enforcement trail; board/queue reconcile +
  terminal card states; TP board-inspection path; advisory attribution
  header; A+ hydration re-verification + CoS as the memory write-back
  actor; new CoS→VM-Xb llm-proxy cross-VM dependency in the endpoint
  table; M1 §1 "unchanged" wording; stale next-action items).
- **2026-11-10 (sixth): DE-POC SWEEP (owner directive).** Removed the two
  root POC documents (`Initial-POC-Findings-Report.md`,
  `POC-Retrospective-and-Insights.md`) — they live verbatim in the frozen
  V1 record (HEAD `2c97797…`, verified); README + book/README pointers
  now cite that location; V2's own findings report + issue ledger are
  build-phase closing deliverables. Retained deliberately: `book/`
  (V1-record provenance) and `deploy/` (V1 evidence baseline; V1 names
  until the `ea-` rename micro-gate). `schemas/message-v1.json` metadata
  de-POC'd (title + description; no contract semantics touched — recorded
  as the §5 "first touch").
- **2026-11-10 (seventh): D12-REV — TWO-TIER WORK BOARD (owner).** Tier 1
  master plan on an external tracker (GitHub Issues default, ADO/Jira
  swap-in; exporter holds the credential, CoS never does) = plan of
  record, human-reviewable, intent audit trail; Tier 2 local Hermes board
  = the pulled working subset driven through approval → submit → report.
  Tracker = plan truth; queue = execution truth; local board = cache.
  Desk-never-door unchanged; fail-safe recovery; write-ahead ordering.
  Full record: `version 2/adr-0001-cos-work-board.md` (ADR-0001 — first
  of a standing ADR class; owner directive: the V2 book gives the
  work-board/approval areas special plain-language attention). Conditions
  1–3 of the third-pass review now applied (§5 allow-list; honest
  approval-hash = retry integrity + tamper-evidence; board durability
  contract). Remaining: condition 4 (runnable judgment corpus) and 5
  (drift pass). Both applied — see the decision-log (eighth) entry.
- **2026-11-10 (ninth): OQ1/OQ4 CLOSED (owner) — no open questions block
  the build.** OQ1: `priority` encoding = coarse enum `high`/`normal`/
  `low` (manager rejects out-of-range; logs the declared value). OQ4:
  the priority field lands **with M1** (field+consumer same gated
  change; `x-max-priority` declared once under the `ea-*` name during
  the rename's queue re-creation). TP assertions 2 and 3 now
  unconditional. **The build phase may open** — sequence: `ea-` rename
  micro-gate → file-level impact inventory + endpoint table →
  build-start security items (registry TLS, service tokens) → staged
  build → M1 / TP-V2-M1.

### Next actions

1. `version 2/V2-M1-cos-design.md` rewritten as DRAFT v2 — **owner review /
   continue design discussion is the next gate**
2. Build: VM-Xa Hermes Agent profile with the CoS persona, desktop gateway
   registration, message-v1 `priority` extension (restart:
   unless-stopped, persona from roster repo, reboot-safe per ch14 §14.8)
3. Gate: TP-V2-M1 — **as amended** (see the M1 design doc §7): structural
   assertions 1–12 including no-submit-without-approval, approval-payload
   hash verification, board-is-not-the-door, credential env + (A+-deferred)
   capability checks, priority (coarse 3-level, with M1 — OQ1/OQ4 closed),
   the judgment corpus as a non-signed pre-gate eval — plus one end-to-end
   (market-analysis example → packages → reports). Prerequisite
   artifacts: the contract test suite and the file-level impact inventory
   (platform §9.5/§9.6).
4. Later V2 open items (from V1 decision log) — *status-corrected per the
   third-pass drift pass:* concurrency beyond sequential (resolved:
   manifest-configurable, default 5; scope-declaration milestone later);
   embeddings provider (resolved as policy: evidence-triggered);
   reboot-surviving stack and contract test suite (**subsumed** — platform
   §9.2/§9.6, no longer separate queue items); dedicated V2 demo repo (+
   1-min GitHub App install when coder-style work arrives); key vault
   (D-secret-vault) on the front-of-house VM (owner-deferred)

## Working protocol (cost reduction — ENABLED 2026-11-08, owner directive)

1. **Bootstrap-by-document:** every session starts by reading this file.
   Decisions and completions are written here IN THE SAME TURN they happen.
2. **One session per workstream;** end sessions at milestone boundaries.
   Retire long sessions freely — continuity lives here, not in the chat.
3. **Delegate bulk work** (repo-wide scans, log analysis, multi-file edits,
   estate inspections) to subagents — they consume their own context; only
   compact summaries return to the main conversation.
4. **In-session output discipline:** targeted queries over full dumps;
   aggregate programmatically and print verdicts; batch tool calls and
   owner questions.
5. **Model discipline:** economical default model; expensive reasoning is the
   exception. Check provider prompt-caching eligibility to flatten the
   resend-cost curve.
6. **De-identification standing rule:** no IPs, usernames, passwords, or API
   keys in any tracked file (placeholders + gitignored env files); the
   Apache copyright headers / LICENSE / NOTICE / AUTHORSHIP author line are
   the deliberate exceptions.

## Repo map (V2)

```
WORKING-STATE.md      this file — read first every session
version 2/            V2 design docs (V2-M1 design lands here)
book/                 V1 record's book, synced @ baseline (15 chapters)
deploy/               V1-proven executable layer, synced @ baseline
schemas/              message-v1 contract (seeded from V1)
decision-log.md       V2 decision log (append-only)
services/             Go services (evolve here as milestones require)
```
