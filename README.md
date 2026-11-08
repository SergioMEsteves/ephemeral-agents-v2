# ephemeral-agents-v2

**Authorship & provenance:** see [AUTHORSHIP.md](AUTHORSHIP.md) — the
concept, designs, and specifications are the author's original work
(conceived May 13, 2026); AI served as directed research assistant, document
creator, and rules-bound implementer.

**Version 2 — the live iteration** of the ephemeral-agents system
(an organization of AI agents: durable orchestration, a role roster,
ephemeral single-task workers, scoped credentials, institutional memory).

## The version boundary

| Repo | Visibility | Role |
|---|---|---|
| [`ephemeral-agents`](https://github.com/arvisdev/ephemeral-agents) | public | **frozen V1 record** — the POC (M0–M5), its signed gates and evidence trail, the findings report, the retrospective, and the book |
| **`ephemeral-agents-v2`** (this repo) | private | **the live iteration** — V2 design, executable layer, and evidence |

**Reference rule:** the V1 record is cited by commit hash, never by
"latest." The V1 baseline this iteration starts from:

```
V1 record: arvisdev/ephemeral-agents @ 14bf62dc81729ed0ece355c30b5b6888d4fbf058
```

The V1 design record is closed to new content (its own baseline rule);
V2 design docs live in `version 2/` here, never in the V1 repo.

## Inheritance from V1

Carried forward unchanged (proven in V1, see the V1 book):

- **Contract:** `schemas/message-v1.json` — the task envelope (seeded here;
  evolves in this repo from now on).
- **Shared infrastructure:** `agent-roster` (the role catalog + human staff
  directory) and the llm-wiki repository serve both versions unchanged.
- **Credential mechanism:** organization app identity → per-task scoped
  tokens, verified revocation.
- **Operational rules:** zero-survivors cleanup, work-order
  self-sufficiency, gates assert outcomes, nothing load-bearing off
  source control (V1 book, Chapter 12).

## Known V2 starting priorities (from the V1 retrospective)

1. Boundary contract tests at every seam
2. Canonical-asset enforcement
3. The coordinator agent (Chief of Staff) in front of the registrar
4. N-parallel concurrency with worktree isolation
5. Per-task isolation upgrade
6. Embedding provider decision (semantic memory)
7. Dependency refresh pipeline; transport hardening

## Layout

```
├── version 2/          V2 design docs (this iteration's doc set)
├── schemas/            contracts (seeded from V1; evolves here)
├── deploy/             the live executable layer (built up as milestones land)
├── services/           Go services
└── decision-log.md     V2 decision log (append-only)
```

## Deliberately not in git

Secrets (`*.env`, app keys, tokens), evidence runs (`deploy/*/evidence/`).
