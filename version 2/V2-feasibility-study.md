# V2 Feasibility Study — functional & non-functional requirements (2026-11-11)

> Companion to the gap analysis (`V2-gap-analysis.md`). Question answered:
> **are V2's functional and non-functional requirements feasible — and does
> meeting them make this a useful and successful project?** Evidence basis:
> the signed gate record (M0–M5, all-PASS), V2's design-review record
> (three passes, verdict ready-with-conditions → all conditions applied),
> and this session's local verification (ported services, unit tests,
> contract suite, judgment corpus).

## 1. The system in one paragraph

A human asks for work in conversation; a persistent Chief-of-Staff agent
(Hermes, on VM-Xa) decomposes it into work packages and proposes them to
the owner; **nothing executes without owner approval** (the defining
safety property); the deterministic Go manager validates every approved
package against the roster and the message contract; RabbitMQ + Temporal
dispatch ephemeral containerized executors (claude-code for code,
hermes-agent for everything else); executors hydrate persona/skills/
memory, do the work in a project repo, write a report, and are reaped
with zero survivors and revoked credentials; reports aggregate back
through the CoS to a single human answer.

## 2. Functional requirements — feasibility

| FR | Requirement | Feasible? | Evidence |
|---|---|---|---|
| FR-1 | Conversational intake: desktop → gateway → CoS, no bespoke API | **Yes** | Native Hermes desktop gateway registry is a shipped Hermes feature (session-token remote connections); the gateway is proven and unchanged (M5 e2e). Residual: the desktop-side registration is workstation work, not research. |
| FR-2 | Request decomposition into work packages (agent_ref, harness, priority, dependencies, additive/corrective) | **Yes, with known limits** | The CoS is a frontier-LLM agent with a 22-agent machine-readable roster (index.json — verified: 22 complete entries, all spec files resolvable). Judgment quality is inherently probabilistic; the design answers this honestly: the judgment corpus (13 fixtures, runnable, verified this session) gates routing correctness at 100% exact-match, and spec quality is owner-reviewed, never auto-scored. |
| FR-3 | Ambiguity → escalate, never guess | **Yes** | Fixtures F11/F12 make it a checked behavior (submit nothing); the ask-before-submit loop (OQ2) is the enforcement backstop. |
| FR-4 | No execution without owner approval; board reflects, never drives, queue state | **Yes — this is the highest-confidence property in the design** | Desk-never-door is enforced structurally (cards reach "submitted" only via the approval flow), gate-asserted (TP assertion 9, negative-tested), and the approval hash adds post-hoc tamper-evidence (TP 10, unit-tested this session: retry integrity + mismatch-reject verified). |
| FR-5 | Deterministic validation: the manager, not an agent, is the contract-enforcer | **Yes** | Carried from the proven manager (the baseline build); the M1 changes (priority enum, approval-hash ledger) are implemented and unit-tested. The manager rejects anything the schema, roster index, or manifest forbids. |
| FR-6 | Ephemeral execution: clone → work → artifact → report, zero survivors, credential revocation | **Yes** | Gate-proven end to end: TC-M3-04 coder path (clone → GLM edit → commit → push), the hermes path (boot → hydration → report), reaper + 0 leftover containers verified, scoped token revoked and verified dead (~75 s). V2 carries this unchanged under ea names. |
| FR-7 | Roster-driven agent selection with harness edge cases | **Yes** | §8 policy encoded in corpus fixtures F03/F04 (security-architect → hermes; data-engineer ETL → claude-code); harness ≠ model is already the roster's structure. |
| FR-8 | Corrective/revision flows mid-stream | **Yes** | D10 additive-vs-corrective modeled in fixtures F09/F10; the baseline build proved follow-on tasks against a live repo (fix-and-rerun cycles throughout M3–M5). |
| FR-9 | Memory: pointers in Hindsight, content in the repo | **Yes** | The hydration contract is gate-proven (M4: pgvector + API + G1–G6 gates); the pointer-store convention is a discipline layered on it, with the pointer-dangling caveat mitigated by the repo's own history index. |

**Functional verdict:** every functional requirement is either already
gate-proven on the estate or is a bounded extension of a proven mechanism. The
only genuinely new runtime behavior is the CoS itself — and its risk is
contained by the design's central move: *the agent proposes, the code
disposes*. A bad CoS proposal cannot execute.

## 3. Non-functional requirements — feasibility

| NFR | Requirement | Feasible? | Evidence / honest limit |
|---|---|---|---|
| NFR-1 | **Security:** no-submit-without-approval; strict credential allow-list (CoS: exactly 4 items, GitHub token explicitly denied); digest-pinned registry pulls; token split (Hindsight write vs read) | **Yes** | Allow-list is assertion 6, assertable both ways; digest pinning is config + a lifecycle check (small); token split is env + firewall config. Residual: everything is design-asserted until the build applies it — the gap analysis owns each item. |
| NFR-2 | **Isolation:** rung A containers + zero-survivors now; A+ (rootless + egress allow-list) as a gated follow-up; B/C trigger-gated | **Yes, in stages** | Rung A is gate-proven. A+ is standard Docker/rootless engineering — feasible, separately gated, not on M1's critical path. Honest limit: a compromised executor shares the execution VM's kernel until A+ lands; the design states this accepted residual. |
| NFR-3 | **Reliability:** reboot survival, dependency-ordered restart, no orphaned approved-but-unsubmitted work | **Yes** | The baseline build's host-reboot incident produced the book's ch14 §14.8 procedure; V2 bakes `restart: unless-stopped` + ordered restart into the artifacts (lesson 5). The board (VM-Xa profile state) is reboot-durable by construction. TP assertion 7 re-proves it here. |
| NFR-4 | **Performance/capacity:** concurrency default 5, priority preemption via x-max-priority | **Feasible, unproven** | x-max-priority is native RabbitMQ; the queue re-declare happens once under ea-tasks (staged). The capacity model + soak test (§9.3) is the honest gap: 5 is a design number until measured — scheduled as its own post-M1 gate, correctly not blocking M1. |
| NFR-5 | **Cost:** model calls through llm-proxy with per-class tokens, spend caps, per-task attribution; economical model default | **Yes** | llm-proxy v3 is gate-proven (mounted, in-path during TC-M3-04); class tokens + caps + logging are config + small proxy work. Attribution is honestly labeled advisory (spoofable header) with enforceable per-container caps as the real control. |
| NFR-6 | **Auditability:** two-tier board = intent trail; gateway/manager logs = enforcement trail; queue = execution truth; approval hash for post-hoc tamper-evidence | **Yes** | Each trail is a distinct, inspectable artifact; TP 9's board-inspection path names how the gate reads the board. The hash's honest limit (evidence, not prevention) is documented, not oversold. |
| NFR-7 | **Maintainability:** additive-only contract evolution; single-repo-per-project manifests; one mapping table for estate traceability; all artifacts committed in-repo (nothing load-bearing on a VM) | **Yes** | Schema evolution rule is enforced by the contract suite (unknown-field rejection verified this session); the ea-rename mapping is committed; the impact inventory (75 rows) makes the build's file surface enumerable. |
| NFR-8 | **De-identification / hygiene:** no IPs, usernames, secrets in tracked files | **Yes** | Standing rule enforced across every artifact this session; `.gitignore` gap (`.env.*`) found and closed before any secret existed to leak. |
| NFR-9 | **Reproducibility:** staged build with `--check-only` dry-runs, gates that name the artifact they prove | **Yes** | The baseline build's install pipeline ran ~15 times to green — the process is itself proven; V2 reproduces it with the lesson fixes pre-applied (§7 lesson map). |

**Non-functional verdict:** feasible across the board, with two honest,
already-scheduled residuals — capacity is unmeasured (soak test gate) and
isolation is rung-A until A+ lands. Neither blocks usefulness; both are
gated upgrades, not risks to the concept.

## 4. Is it a useful and successful project?

**Yes — with the success criteria made explicit:**

1. **Useful (does it do real work?):** the baseline build already proved the hard part —
   an ephemeral agent doing a real coding task on a real repo, end to end,
   with cleanup and revocation, reproducibly across ~15 pipeline runs.
   V2's addition — judgment at intake under human approval — converts a
   proven task-executor into a system a person can actually delegate to
   conversationally. That is a real capability jump, built on proven
   foundations rather than new ones.
2. **Successful (by its own declared standards):** the project defines
   success as gate-passed, evidence-signed milestones, not demos. M1's
   gate (TP-V2-M1, 12 assertions + corpus + e2e) is strict, and the
   design survived three adversarial review passes converging to
   *ready-with-conditions* with all conditions closed. A project whose
   primary risk was design error has retired that risk class.
3. **The three things that would make it fail — and their answers:**
   - *An unapproved submission executes* → structurally impossible by
     design (desk-never-door), negatively gate-tested, hash-audited.
   - *The CoS routes badly* → corpus blocks signature at <100%; the
     manager still validates everything; the owner sees every proposal.
   - *The build never converges on real hardware* → the process is the
     most-proven artifact in the record (the baseline build's full install history);
     V2 adds inventory-first, contract-tests-first, and staged gates.

**Residual risks (owned, not open):** execution risk on the estate
session (orphan bring-up, rename steps — scripted and checklist-driven);
CoS behavioral quality (gated by the corpus, bounded by approval);
capacity assumptions (soak gate). None is a feasibility threat.

## 5. Conclusion

The functional requirements are feasible — most are already proven, and
the genuinely new one (the CoS) is deliberately confined where failure
is safe. The non-functional requirements are feasible within the chosen
isolation rung, with capacity as the one number awaiting evidence. The
project is ready to build: the gap analysis enumerates every remaining
item, each owned by a named stage. **Recommendation: declare the build
start and let the estate session execute the pre-build checklist.**
