# Chapter 6 — The Roster

> **V2 pointer.** The thesis-level treatment of the roster — why roles are
> written not assumed, the prose-persona decision, the single-task contract,
> and how a role is born — lives in the V1 book (`book/ch6-the-roster.md`)
> and is unchanged in principle. This chapter covers the V2 delta: the
> roster becoming the *only* catalog, the three hydration files as a
> standing contract, and the index that both a registrar and a test suite
> now read.

> **In plain terms.** The staff directory is still one repository of job
> descriptions. V2's change is a consolidation: the separate "machine
> catalog" that the design docs once planned was never built — instead, the
> staff directory *is* the machine catalog. One folder per role, three files
> in each, one index to search. The payoff is the same rule the build keeps
> re-learning: nothing load-bearing may live in two places.

## 6.1 What carries forward

V1's roster decisions all stand: files in a version-controlled repository,
not rows in a database; personas as prose, not parameters; the roster as
the routing surface (job titles *are* the routing table); and the
no-secrets property — the roster remains the most public artifact in the
system. The three-department organization (bus-org, ea-org, ephemeral-org)
is unchanged, and the `eph-` workforce still carries the single-task
contract in every behavioral spec: exactly one work package, produce the
artifact, write the report, exit; flag adjacent work; fail loudly.

## 6.2 The catalog realization: one directory, both readers

The V1 design documents had planned a second artifact — a separate
machine-readable "available agent list" the manager would match against.
D-catalog-realization (2026-11-08, recorded in the M5 decision log) retired
that plan before it could be born: **the machine-readable catalog the
manager matches against and the executors hydrate from is the agent-roster
repository itself** — the same repo that holds the human staff directory.

The rationale is V1's Lesson L4 turned into architecture: one source of
truth serves both readers, so there is no "documentation copy" that can
drift from the runtime copy. The version-closure rule shaped *how* the
decision was recorded — the V1 contract doc stays as the baselined design
record, untouched, and the realizing decision lives in the decision log
(agent-roster commit `f9ec562` for the catalog files; cross-references in
`a1e7dea`). You do not edit a baselined document to change its future; you
record the decision that supersedes it.

The V2 build then ran on the realized catalog end to end: the manager's
environment points at the roster repository (`AGENT_LIST_REPO`), the
executor persona match against the roster is a gate assertion (TP-M3:
boot-time p50 ≈ 1.4 s with persona match verified), and a live smoke run
routed a "risk assessment" capability to
`ephemeral-org/eph-risk-assessment-analyst` and hydrated the role from the
folder. The M5 end-to-end also taught the flip side: an injected test used
the capability `dev`, which no real catalog entry matches — the fix used
the exact roster ref (`ephemeral-org/eph-backend-engineer`), and ledger
entry 12's rule now says it in general: *the injected capability must be a
real catalog ref.* A catalog with no `dev` entry is not a defect; a test
that pretends otherwise is.

## 6.3 The three hydration files, per folder

Every executable role folder carries exactly the three files the executor
contract hydrates at boot:

| File | What it holds |
|---|---|
| `persona.md` | the professional archetype — experience, communication style, behavioral traits |
| `skill-and-tools.md` | the craft (what the role can do) and the instruments (what it may use) |
| `behavioral-spec.md` | the operating rules — work pattern and the completion contract the whole system leans on |

Three files, no more — V1's maintainability constraint, unchanged. What is
new in V2 is *who else* hydrates from the contract. The chief-of-staff
milestone makes the hydration contract's first **persistent** consumer: the
resident CoS hydrates its persona files from `bus-org/chief-of-staff/` in
the same roster, at the same boot, by the same mechanism as the one-shot
`eph-` workers. A contract that had exactly one kind of consumer now has
two — and the two kinds are the system's deepest boundary (ephemeral
workforce vs. durable staff). The roster serves both because the contract
never assumed either.

V2's gate evidence for the file contract is measured, not asserted: the M3
boot-time tables (p50 ≈ 1433 ms, reproducibility within the recorded delta)
are the hydration contract running against the real roster, per run.

## 6.4 `index.json`: the shape, and who reads what

The catalog's machine-readable half is a root `index.json` — one entry per
executable role, 22 `eph-*` entries, in the wrapped shape:

```json
{
  "agents": [
    {
      "ref":      "ephemeral-org/eph-risk-assessment-analyst",
      "name":     "Risk Assessment Analyst",
      "role":     "risk assessment analyst",
      "folder":   "ephemeral-org/eph-risk-assessment-analyst",
      "skills":   ["risk register", "…"],
      "spec_ref": "ephemeral-org/eph-risk-assessment-analyst/behavioral-spec.md"
    }
  ]
}
```

Each field keeps its single consumer (V1's assignment, unchanged): `role`
and `ref` are what the manager matches a request's capability against;
`folder` is what the worker hydrates from (the `#folder` half of the work
order's `agent_ref`); `skills` are human-facing keywords; `spec_ref` is the
fallback instruction pointer.

Two things changed around the shape, though:

1. **The wrapped shape is the realized shape.** V1's book recorded that the
   index *accepted two shapes* (bare array and wrapped object) because the
   build's real shape had differed from the documented one. V2's catalog
   realization commits the wrapped `{"agents": […]}` form as the
   canonical shape — while consumers still parse both (the parser accepts
   either), because a registrar that refuses to be the reason work stops
   remains a property worth keeping.
2. **The index is now a standing test target.** The V2 contract test suite
   (`deploy/contract-tests/run.py`) validates the roster itself as a
   prerequisite artifact: the index is present and non-empty, every entry
   is shape-complete and unique, and every `spec_ref` resolves to a real
   file — with schema-negative message cases beside it (out-of-range
   priority, bad hash pattern, unknown field). The V1 build discovered
   catalog-shape mismatches *during* gates; the V2 build refuses to reach
   a gate with one. 14/14 green at the pre-build gap-closure commit
   (`f451791`).

## 6.5 Design decisions and alternatives (V2 delta)

**Decision: the roster is the one catalog (D-catalog-realization).**
Alternative: build the planned separate agent list — rejected: it would be
a second, machine-facing copy of information the roster already holds, and
the only question about two copies is *when* they diverge. The catalog rule
V1 applied to the llm-wiki ("owner-curated only") also applies naturally:
the roster's prose is curated by people; the index is small enough to
curate alongside it.

**Decision: the index shape is canonical, the parser stays tolerant.**
Alternative: parse only the canonical shape — rejected: the tolerance costs
one line and has already saved a build once; strictness belongs in the
schema and the tests, not in a reader's assumptions about history.

**Decision: the roster joins the contract test suite as data under test.**
Alternative: keep roster validation as a gate-time check inside the
milestone that consumes it — rejected: the roster is upstream of every
milestone; a shape break there should fail a cheap, early, standing suite,
not a milestone's signed run.

## 6.6 What the roster does not do

The V1 boundaries hold: it does not pick who is chosen (that is judgment's
work, the CoS's selection per the M1 design); it does not define how a
worker executes (that is the harness, Chapter 7); it holds no secrets. V2
adds one more negative: it does not *discover* capabilities. The index
knows only what is written in it — the `dev` incident settled that — so a
capability that does not resolve is a roster gap to be authored, not a
routing bug to be fixed. The roster remains the organization's promise to
itself, now with a test suite that checks the promise every run: every
role we can staff is written down well enough that a stranger — human,
machine, or contract test — could do the job from the files alone.
