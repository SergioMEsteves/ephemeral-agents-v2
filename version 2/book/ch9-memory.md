# Chapter 9 — Memory

> **In plain terms.** Workers forget; the organization must not. V1 built
> the filing cabinet; V2 re-organized it: the shared knowledge library
> became **a plain git repository** that every worker shallow-clones at
> boot, the memory store moved to its **own stack beside V1's** — and the
> build's one attempt to skip the separation took V1's memory system down
> mid-build, which is the incident this chapter tells honestly.

## 9.1 The line carried forward — and the three-piece separation

The V1 discipline holds: a worker holds nothing between tasks; before it
dies it makes one structured write; at boot it makes one read. V2 sharpens
the architecture into three deliberately separated pieces:

| Piece | What it is | Where it lives |
|---|---|---|
| **The writer** | The agent that finished the work and decides what deserves an entry | The front-of-house organization |
| **The store** | The memory service, holding **pointer entries only** | The memory VM — V2's own stack |
| **The content** | The actual reports and documents | The project repository — sole source of truth |

The pointer-store convention is the load-bearing change from V1's
"store holds the learnings." A pointer entry records *that* work happened,
what it was about, and *where the artifact lives* — and a pointer cannot
go stale the way a held copy would, because the repo is always current
truth. The known cost is named (a pointer can dangle if an artifact moves
or a branch is pruned), and the mitigation lives in the repo itself: the
project's own history index and git history are the durable record behind
the pointer.

## 9.2 The wiki became a repository (D-wiki-git)

V1's shared knowledge library was served; V2's decision is that **the
llm-wiki is not a service at all — it is a git repository.** The
mechanics:

- **Boot-time hydration by clone.** The executor entrypoint shallow-clones
  the wiki repo at boot (depth 1) using a fine-grained read token, alongside
  the roster clone and the memory read. There is **no retrieval API and no
  wiki URL anywhere in the estate config** — the knowledge base is
  reached exactly like the code the org edits: git.
- **Graceful degradation, unchanged.** No token, unreachable repo → the
  boot proceeds without the wiki, logged in the self-report's source
  fields. Never fails the task.
- **The gate asserts the absence of infrastructure.** The M4 gate's
  isolation case verifies *zero wiki containers and images* — proving the
  decision survived implementation. A wiki that needed running would be a
  service; this one is content.
- **Curation is human-owned, append-only, and itself in git.** The
  curation decision (D-curation) names the human-in-the-loop as owner with
  a CHANGELOG convention in the repo. The gate exercised a full curation
  cycle: a new standard doc pushed (one commit), its CHANGELOG entry
  (another), then a fresh shallow clone from a spawned container that
  found the new document *and* all previously curated lookups — new
  knowledge live, no regression, in two commits.

Why git beats a service here: the wiki's readers are executors that
already clone repos, already hold read tokens, and already degrade
gracefully at boot. A retrieval API would have added a service to keep
alive, a protocol to version, and a second truth about what the wiki
contains. Git makes the wiki's deployment story, access story, and
history story all be the *same* story as everything else the
organization touches.

## 9.3 The store beside, not instead: ea-hindsight on 8082

The memory service runs in V2's own stack on the memory VM, with V1's
stack untouched and running beside it:

- **Compose project `ea-hindsight`** with `ea-hindsight-*` container names
  — distinct from V1's project on the same VM.
- **Its own volume** — V2's memory starts clean; V1's data volume is
  never touched.
- **Port 8082** — V1 keeps 8081; two memory systems, one VM, no shared
  port, no shared storage.
- **A separate Postgres instance** (the pgvector image) — its own engine,
  its own host, distinct from the broker estate's databases; the
  isolation case verifies engine + host + volume, all three.

The fresh-store property doubles as a routing proof: V2's store contained
only V2-era entries — V1's rows absent from every read result — which
verifies both that reads route to the right stack *and* that no data
leaked across the boundary. The read/write contracts are V1's (scoped
cross-task recall at boot, one learning written at end, the hydration
marker line in the task log), and the self-report now carries **three
sources** — roster, wiki, memory — each true/false, plus measured boot
time, so every gate can see exactly what a worker inherited.

## 9.4 Case study: the takeover (ledger 8)

The build's one coexistence violation came from the mildest possible
cause: inheritance.

**The symptom.** Deploying the m4 memory stack *replaced V1's containers
and reused V1's data volume*. V1's memory system went down mid-build —
the exact failure the whole `ea-` naming program existed to prevent,
caused by one field: the compose kept V1's project name and V1's volume
name, so "bring up V2's memory" was interpreted as "reconcile the stack
named `hindsight`," and the reconciliation removed V1's containers.

**The wrong assumption.** That compose project names and volume names
inherited from V1 were safe — that naming was a V1-rename concern, not a
live collision mechanism.

**The root cause.** Compose treats project name as identity. Every other
V2 stack had followed the naming rule; m4 was the exception, and the
exception was *caught by the gate discipline* (the coexistence checks
around the deploy) and fixed in one commit: project `ea-hindsight`,
containers `ea-hindsight-*`, own volume, port 8082.

**The restoration sequence is part of the fix.** The rule reads: *every
V2 compose sets an `ea-` project name, `ea-` containers, and an own
volume; the restoration sequence is part of the fix runbook, not an
afterthought.* Executed in order: takeover stack down → V1 up from its
own deploy path (healthy on 8081) → V2 up (healthy on 8082) — both
stacks coexisting with distinct volumes, V1's data intact throughout.

The finding this incident fed (findings §4.1) is worth keeping verbatim
in spirit: **one `name:` line was the difference between coexistence and
takeover** — and the estate went on to host two live memory systems on
one VM for the rest of the build, which is the "coexistence is the
cheapest isolation" data point in its purest form.

## 9.5 The contracts, measured

The M4 gate measured what V1 asserted:

- **Hydration latency ×3**: totals **0.79–0.92 s** per boot — the wiki
  clone dominates (0.6–0.73 s), the memory read is ~10 ms (store-local),
  the catalog fetch ~0.17 s. Against a 600 s TTL budget that is ~99.8%
  headroom: memory costs nothing operationally, which is why workers
  actually hydrate.
- **Cross-task recall proven live**: a task's learning returned in a
  *different* task's q-driven read payload — the org-not-worker line as
  a test result, with the full read/write JSON filed as evidence.
- **End-to-end from a fresh store**: the first real hydration read the
  V2 stack — not V1's — proving wiring *and* isolation in the same
  observation.

The degradation rules are unchanged and still load-bearing: memory
unreachable at boot → proceed without it, logged; wiki token absent →
clone skipped, source marked; the pipeline's guarantees come from the
durable core, not its satellites.

## 9.6 Design decisions and alternatives

**Decision: pointer store over content store.** Alternative: the memory
service holds the reports (V1's shape). Rejected: a held copy goes stale
and creates a second truth; pointers keep the repo authoritative and the
store small. Cost named: dangles; mitigations: the repo's own history
index.

**Decision: the wiki is a repository, not a service.** Alternative: a
retrieval endpoint. Rejected: it would add infrastructure to a content
problem the org's existing tooling already solves — cloning, diffing,
authenticating, and curating via the same git mechanics as every other
artifact. The gate's zero-wiki-containers assertion keeps the decision
honest against future drift.

**Decision: an own stack per organization.** Separate project, containers,
volume, port, and database instance — not a shared memory service with a
scope column. The takeover incident (§9.4) is the argument: sharing
infrastructure between two live organizations makes every deploy a
negotiation; separate stacks make it a non-event.

**Decision: embeddings stay evidence-driven (D-embed).** The store runs
the zero-vector fallback: writes succeed, reads are q-driven and
functional (proven by the cross-task cases), and *semantic ranking*
remains the named open item — to be plugged in only if pointer recall
proves poor in practice, behind the same one-service-owns-the-provider
pattern as Chapter 8's proxy. An incomplete capability that is labeled
is a plan; hidden, it would be a defect.

## 9.7 What this buys

The organization now exhibits, measured: **task N+1 is better because task
N happened** — and the knowledge a new worker inherits arrives through
two plain, inspectable mechanisms: a git clone of everything the humans
curated, and a scoped read of everything the agents learned. The takeover
incident stands as the estate's proof that the boundary between
organizations is real: V2 broke it once, restored it in three steps, and
every coexistence rule in Chapter 11 now carries the scar tissue of that
one `name:` line.
