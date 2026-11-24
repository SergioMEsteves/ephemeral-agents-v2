# Architecture Review & Findings Report — ephemeral-agents-v2

**Audit date:** 2026-11-23 (post-publication audit)
**Auditor:** Hermes Agent (architecture review skill, "7 Architectural Design Laws of Senior AI Engineers")
**Scope:** The full V2 system as built — Hermes Desktop → CoS Hermes profile → deterministic Go manager → RabbitMQ/Temporal → ephemeral Docker executors — across the four-VM PVE estate, milestones M0–M5 + m1-cos, all gates signed, repository public at audit time.
**Method:** Law-by-law inspection against the seven architecture design laws (tool calling, planning, memory, multi-agent, human approval, sandboxed execution, evaluation), grounded in the live code/config (compose files, services tree, CoS profile, roster) and the signed gate record. Findings categories: P0 critical, P1 major gap/architectural debt, P2 minor optimization, Compliant.

---

## 1. Executive Summary

* **Architectural Posture**: **Strong and unusually honest.** The architecture embodies the audit's meta-principles directly: judgment is confined to the CoS at the door, everything behind it is deterministic code, credentials are scoped-per-task and revoked at reap, and the build record documents its own deferred gaps (the isolation ladder, D-secret-vault) rather than hiding them. Remaining risks are concentrated in execution-plane network egress and memory-injection governance — both known, both deferred deliberately, neither silent.
* **Top 3 Priority Fixes**:
  1. **Executor egress filtering (P1, top)** — executors today run with unrestricted network reach on the shared execution VM; the egress allow-list is scheduled as the A+ rung but nothing currently bounds where a task container can connect.
  2. **Memory-injection governance (P1)** — `M4_MEMORY_HYDRATE` injects stored Hindsight content into executor/CoS context with no provenance marking or trust boundary; a poisoned memory entry (e.g., via a task's own repo content) re-enters future prompts as apparent authority.
  3. **Continuous evaluation (P1)** — the judgment corpus is a good harness but runs manually, only on CoS persona change; no regression gate fires on model, prompt, or tooling changes, so behavioral drift between audits is invisible.

---

## 2. Seven Laws Evaluation Matrix

| Architectural Law | Status | Primary Finding / Observation |
| :--- | :--- | :--- |
| **1. Tool Calling** | Compliant | App-mediated control is the architecture's spine: the agent proposes, `ea/manager` validates, lifecycle executes. Executors never hold raw credentials — single-task GitHub App tokens, revoked at reap (proven 200→401 in TP-M5). Roster index gates "who may start work" at two layers (CoS intake + manager validation). |
| **2. Planning** | Compliant | Static workflow = deterministic Go; the only agentic loop (CoS decomposition) sits behind the human approval gate with a stable work-package schema. Bounds exist: TTL 1800 s hard cap, `MaximumAttempts: 2`, wait-then-follow-on correction semantics (D10) instead of mid-flight mutation. |
| **3. Memory** | P1 | Context hygiene is good (durable memory is pointer-based, committed `cos-state/state.json`, executors hydrate on boot). Gap: no memory governance — no provenance/trust marking on hydrated content, no TTL/staleness policy on Hindsight entries, no poisoning defense; memory is written by executors and re-read by executors (self-referential loop). |
| **4. Multi-Agent** | Compliant | Clear value threshold: three orgs with distinct jobs (judgment / orchestration / execution); workers are single-task and ephemeral, so no sprawl. Handoffs are explicit (work order → queue → report → CoS aggregation). |
| **5. Human Approval** | Compliant | Textbook pre-action gating: nothing executes without human sign-off on the proposal; the approval hash is tamper-evidence bound into the message the manager validates; the policy engine is the deterministic manager, not the LLM. |
| **6. Sandboxed Execution** | P1 | Control/execution planes are separated by machine and network. But the sandbox is rung A: co-located Docker containers, shared kernel, root daemon on the execution VM, and no egress filtering. The ladder (A → A+ → B → C) is documented and gated — managed debt, not oversight. |
| **7. Evaluation** | P1 | Hybrid verification exists and is strong: exit-code/schema gates, zero-survivors assertions, trivy scan, 13-fixture machine-scored corpus at 100% required. Gaps: corpus is manual/episodic, Layer-2 judgmental review is unowned on a schedule, and per-task traces live in per-task log volumes but no aggregated trajectory evaluation runs over them. |

---

## 3. Detailed Findings & Recommendations

### Law 1: Tool Calling — Compliant
* **Current state**: Every consequential action is app-mediated: CoS proposal → manager (schema, roster, manifest, TTL, approval-hash) → lifecycle spawn → scoped token → reap + revoke. Desktop is stateless and holds no estate credentials.
* **Assessment**: The architecture's strongest law. The dual gate (a compromised CoS still cannot exceed the validated envelope; the manager cannot act on what was never approved) is the core safety property.
* **Minor (P2)**: Executor-harness tool/interface descriptions could get the same strictness review the roster receives; low risk today since executors are one-shot.

### Law 2: Planning — Compliant
* **Current state**: Decomposition is the CoS's judgment call; execution paths are deterministic code. Ambiguity → clarifying question, submit nothing (D7d). Corrections wait for task completion and arrive as revision packages to the successor — no mid-flight mutation of a running agent.
* **Assessment**: The wait-then-follow-on pattern (D10) converts "interrupting agents" from a reliability hazard into a bounded correction loop — a senior design choice.
* **Minor (P2)**: TTL/retry timings are uniform defaults; per-task-class TTL budgets would tighten resource bounds without added complexity.

### Law 3: Memory — P1
* **Vulnerabilities**: (a) Hydrated memory blocks enter prompts without provenance markers, so stored text is indistinguishable from operator instruction; (b) no staleness/TTL policy on Hindsight entries (a convention learned months earlier is still "true" indefinitely); (c) the write path is agent-controlled — an executor can persist guidance its successors treat as authoritative.
* **Remediation**: Mark hydrated blocks as untrusted data with a defined trust boundary; add per-entry source + timestamp and a staleness re-validation rule; consider requiring the CoS (not raw executor output) to be the write path for anything load-bearing.

### Law 4: Multi-Agent — Compliant
* **Current state**: The value threshold is plainly met — the separation buys real safety (executor can't approve; CoS can't execute). Workers are single-task, so agent sprawl is structurally impossible.
* **Observation (P2)**: The manager's validation duty list will grow with each milestone; keep it a pure validator — moving any judgment into it would erode the LLM/code boundary.

### Law 5: Human Approval — Compliant
* **Current state**: Approval precedes any submission; the hash pins exactly what was signed; rejections return to the CoS rather than proceeding degraded. The deterministic manager — not any model — decides what requires approval.
* **Assessment**: Cleanest implementation of this law in the estate. No findings.

### Law 6: Sandboxed Execution — P1
* **Current state**: Execution plane is isolated on its own VM with a per-task log volume, single-task containers, zero-survivor reap, and an independent orphan-monitoring reaper.
* **Vulnerabilities**: Rung-A realities — shared kernel with root Docker daemon available to a broken-out container; no network egress allow-list (a task container can reach the LAN and the internet); credentials, while scoped, are reachable from within the container by design.
* **Remediation**: Execute the already-planned A+ rung (rootless Podman + egress allow-list) before any workload beyond trusted owner repos touches the estate; gVisor/micro-VM remain trigger-gated, which is correct.

### Law 7: Evaluation — P1
* **Current state**: Strong deterministic assertions (zero survivors, digest-identical images, trivy, token lifecycle, e2e with failure injections) plus the 13-fixture corpus as a persona-regression harness.
* **Gaps**: No continuous/CI trigger for the corpus; Layer-2 judgmental review has no cadence or owner; no automated trajectory review over the retained per-task logs; the corpus does not yet cover the failure-behavior surface (rejections, TTL kills) it helped specify.
* **Remediation**: Run the corpus as a gate step on any change to CoS profile, model, or tooling; add a lightweight periodic trajectory sample review from the per-task log volumes.

---

## 4. Autonomy vs. Complexity Analysis

* **Where autonomy creates justified value**: CoS intake — decomposition, ambiguity detection, prioritization — is the one place a model must reason, and it is fenced at the door behind human approval. Everything the user experiences as "agentic" happens before the deterministic boundary.
* **Where deterministic code already wins** (and correctly does): schema/roster/manifest/hash validation, credential issuance and revocation, retry/TTL policy, reaping, report routing, queue topology. Zero agent logic lives in these — verified against the services tree at audit time.

## 5. Remediation Roadmap

* **Phase 1: Critical Safeguards (P1, critical-path)** — Executor egress allow-list + rootless Podman (the scheduled A+ rung), before any workload beyond trusted owner repos.
* **Phase 2: Architectural Stabilization (P1, governance)** — Memory provenance/staleness policy; corpus-on-change gate for CoS profile, model, or harness changes; Layer-2 review cadence.
* **Phase 3: Operational Maturity (P2)** — Per-task-class TTL budgets; trajectory-log review over retained task logs; interface-description strictness pass on executor tooling.

---

**Bottom line**: 4 of 7 laws fully compliant, 3 at P1 — and every P1 is a known, documented deferral rather than an undiscovered flaw, which is itself evidence the architecture's self-audit discipline works. The single highest-leverage next build is the A+ rung; it converts the two biggest residual risks (egress, root daemon) into closed items and completes the isolation ladder's second step.

---
*Remediation status (updated 2026-11-24): Phase 1 network half executed — executor egress allow-list live on the execution VM (D-APlus-egress, TP-H1a all-PASS, `deploy-v2/h1/tp-h1a-results.md`). Remaining: H1b rootless Podman (engine half), H2 memory governance, H3 continuous evaluation — per ADR-0003.*
