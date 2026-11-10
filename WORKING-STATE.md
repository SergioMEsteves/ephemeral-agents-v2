# WORKING-STATE.md — ephemeral-agents-v2 session bootstrap

> **Read this first in every new session.** This file is the living continuity
> record: current state, decisions, open questions, next actions. Update it in
> the same turn a decision is made or a step completes. Context lives HERE
> (cheap, read once) — not in the conversation (expensive, resent every turn).

*Last updated: 2026-11-08*

## Current position

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

### Open questions (settle before/during design doc)

- **Q1 — desktop↔CoS connection:** recommended = authenticated HTTP API on
  the front-of-house VM consumed by the desktop Hermes as a tool (fits the
  estate's API pattern; desktop stays credential-free). Alternatives: MCP
  server, SSH/CLI. AWAITING OWNER.
- **Q2 — approval mode:** recommended = ask-before-submit (CoS proposes the
  decomposition, owner approves, then it submits); autonomous later once
  trusted. AWAITING OWNER.

### Next actions

1. Owner answers Q1/Q2 → write `version 2/V2-M1-cos-design.md` (connection
   procedure, runtime shape, credential contract — one model key only, no
   GitHub token, no queue access — conversation protocol, gate/TP plan,
   rejected alternatives)
2. Build: CoS container + compose on the front-of-house VM (restart:
   unless-stopped, persona from roster repo, reboot-safe per ch14 §14.8)
3. Gate: TP-V2-M1 — structural assertions (all proposed refs exist in
   index.json, manager validation passes, TTL policy, model-call failure
   behavior, credential scope, reboot survival) + one end-to-end
   (market-analysis example → packages → reports)
4. Later V2 open items (from V1 decision log): concurrency beyond
   sequential, embeddings provider (zero-vector fallback today),
   reboot-surviving stack (restart policies / umbrella compose), contract
   test suite, dedicated V2 demo repo (+ 1-min GitHub App install when
   coder-style work arrives), key vault (D-secret-vault) on the
   front-of-house VM

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
