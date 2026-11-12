# ADR-0001 — The Chief-of-Staff two-tier work board

*Status: Accepted (owner, 2026-11-10). Supersedes the single-tier board of
D12 and the `cos-state/state.json` mechanism before it. Companion to
`V2-M1-cos-design.md` §2 (D12/D12-rev), §6.8, §7; `V2-platform-design.md`
§2, §9. Written for senior technical staff; the plain-language treatment of
this decision belongs to the V2 book's Chief-of-Staff chapter.*

## Context

The V2 Chief-of-Staff (CoS) is a persistent Hermes agent on the
front-of-house VM that converts conversational requests into proposed work
packages. Three prior state mechanisms were considered and each failed a
stated constraint:

1. **Conversation/session state only** — lost on reboot; approved-but-
   unsubmitted work could be orphaned (the state the M1 gate must
   explicitly protect, TP assertion 7).
2. **A state file committed to the project repo** (`cos-state/state.json`)
   — durable and reviewable, but requires the CoS to hold a GitHub
   credential, violating the credential contract (M1 design §5: the CoS
   holds no GitHub token). It also creates a push-race with the ephemeral
   executors that push to the same repo.
3. **A single local kanban board** (D12, first revision) — clean on
   credentials (the board is native profile state; no key needed), but it
   made the CoS's sole recovery source live on exactly one VM, trading
   away off-site durability without naming the cost, and had no
   corruption/fail-safe story.

Separately, three reviews converged on requirements any state mechanism
must satisfy: survives a total VM-Xa loss; never grants the CoS new
credentials; can never become a path by which work *starts* (the queue —
RabbitMQ/Temporal — is the only execution truth; "the agent proposes, the
code disposes"); provides an intent audit trail distinguishable from the
enforcement audit trail; and supports the owner's review of a proposed
decomposition before approval (ask-before-submit, Q2).

## Decision

A **two-tier work board**:

**Tier 1 — the master plan (external tracker).** The CoS decomposes the
behavioral specification into the complete plan — every intended work
package, with agent_ref, behavioral_spec, priority, ttl, and dependency
edges — and the plan is published to an external tracker. **GitHub Issues
is the default; the exporter is tracker-agnostic, so Azure DevOps Boards
and Jira are swap-in targets.** A dedicated **exporter** component on
VM-Xa performs all tracker I/O and holds the tracker credential (staged
gitignored per the platform design's staging note). The CoS composes plan
content; it never holds a tracker key and never performs tracker I/O.

The master plan is the **plan of record**: it survives a total VM-Xa loss
by construction; it is human-reviewable in the approval flow (the owner
reviews the proposed decomposition in the tracker); its history is the
**intent audit trail**.

**Tier 2 — the working set (local Hermes board).** The CoS pulls a logical
subset of master-plan items — unblocked by the dependency graph,
priority-ordered, within the `max_parallel_agents` window (default 5) —
onto its native local board, and drives that subset through the
approval → submit → report loop. The working set is a **cache**, not a
record.

**Direction of truth, per tier:**

| Artifact | Authoritative for |
|---|---|
| External tracker (master plan) | the *plan* — what is intended, in what order |
| Gateway / manager / RabbitMQ / Temporal | *execution* — what actually happened |
| Local board (working set) | nothing; a cache between the two |

Status flows **up** (local transitions → tracker status updates, via the
exporter). Plan content flows **down** only via an explicit subset-pull
initiated by the CoS. The exporter is offline-tolerant: if the tracker is
unreachable, the CoS continues working locally and syncs when it returns.

**Invariants (unchanged from D12):**

- **The desk is never the door.** Neither tier can start work. An item
  becomes executed work only through the owner's approval → gateway →
  manager validation → queue. Gate-asserted (TP assertion 9: no code path
  moves a card to "submitted" except the approval flow; the board
  reflects, and never drives, queue state).
- **Credentials stay out of the CoS.** The exporter holds the tracker
  credential; adding the tracker does not widen the CoS allow-list
  (§5's four-credential list is unaffected).
- **Fail-safe recovery.** After any restore or reboot, a card whose
  approval state is ambiguous is surfaced to the owner — never
  reconstructed optimistically, never submitted from unproven state.
  Write-ahead ordering makes the crash window deterministic: approval is
  recorded on the card *before* the submit attempt; "submitted" is
  recorded only after gateway acknowledgment.

## Consequences

**Positive:**
- Durability is achieved at the plan level: the state the M1 gate must
  protect (approved-but-unsubmitted work, backlog, dependencies) survives
  any VM-Xa failure without new credentials and without coupling the CoS
  to GitHub.
- The owner reviews decompositions in a purpose-built review surface
  (the tracker) rather than in free-form conversation — directly
  hardening the ask-before-submit control against habituation.
- Three audit trails are now cleanly separated: tracker history = intent;
  local board history = working intent; gateway/manager logs =
  enforcement. (The observability minimum in the platform design cites
  this split.)
- The subset-pull is the concrete realization of the CoS's
  prioritization/backlog duty (D7b) and composes naturally with
  `max_parallel_agents` and the dependency rules.

**Negative / accepted costs:**
- A new component (the exporter) and a new credential class (tracker
  token, exporter-held) — both join the §9.1 staging note and the
  file-level impact inventory.
- The local board can drift from the master plan between syncs; the
  reconcile rule is: on boot and on demand, submitted task_ids are
  reconciled against gateway truth; plan deltas flow only via explicit
  re-pull.
- Tracker availability becomes a dependency of *plan persistence* (not of
  execution): offline-tolerant, but a long tracker outage means unsynced
  local state — acceptable at M1's single-operator scale, and the
  exporter's queue is bounded.
- Terminal card states (manager-rejected, voided, TTL-failed) must be
  modeled on both tiers (archived-with-status) so the failure behaviors
  in M1 §6 have a place to land.

**Neutrals:**
- Tracker choice (GitHub vs ADO vs Jira) is a build-time configuration
  decision, not an architecture decision — the exporter interface is the
  abstraction point.
- The A+ isolation rung does not touch either tier (both live on VM-Xa or
  off-VM; executors never touch either).

## Alternatives considered

1. **State file in the project repo** — rejected: credential contract
   violation; push-race with executor pushes; couples CoS work state to
   the project repo's history (noise in the work artifact tree).
2. **Single local board with ad-hoc export** (D12 first revision) —
   superseded by this ADR: durability was bolted on rather than
   structural, and the export target was unspecified.
3. **External tracker as the *only* board (no local tier)** — rejected:
   every CoS transition becomes a synchronous tracker API call; the work
   loop gains latency and a hard availability dependency; the CoS would
   effectively need tracker write access for transitions (credential
   contract pressure). The two-tier split keeps the hot path local.
4. **Database-backed state store on VM-Xa** — rejected for M1: another
   stateful component to build, back up, and gate; the tracker already
   provides durable, reviewable storage with zero new services.
