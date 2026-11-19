# Estate → ea name mapping (ea- rename)

> Recorded at the opening of the V2 build phase per
> `V2-platform-design.md` §1 and the rename micro-gate (§9.7).
> Scope note: the pre-rename evidence baseline is preserved in the owner's
> archive, not in this repo; this repo carries the `ea-`-named deploy layer only. Every V2-owned component created from here on
> uses the `ea-` family from birth; nothing in V2-owned code re-defines
> these mappings.

| Estate name (first organization) | ea name | Applies to |
|---|---|---|
| `poc-net` (docker network) | `ea-net` | V2 compose layer |
| `poc/hermes-ephemeral:1.0.0` (image) | `ea/hermes-ephemeral` | executor image (re-tag, digest-identical) |
| `poc/claude-coder:1.0.0` (image) | `ea/claude-coder` | executor image (re-tag, digest-identical) |
| `poc/{topic-bridge,lifecycle,worker,executor-stub,hindsight-api,gateway,manager}` (image repos) | `ea/{…}` | the other 7 deployed images (re-tag, digest-identical) |
| `POC_*` env vars (`POC_NETWORK`, `POC_EXECUTOR_DEFAULT`, `POC_IMAGE_HERMES`, `POC_IMAGE_CODER`, `POC_IMAGE_DEFAULT`, `POC_IMAGE`, `POC_TTL_DEFAULT`, `POC_CIDR`, `POC_REGISTRY`, `POC_DOCKER_DEBUG`) | `EA_*` (same suffixes) | V2 services + compose env wiring |
| `poc-*` container / queue names | `ea-*` | V2 compose service names; RabbitMQ queues (queues re-created once under `ea-*` with the `x-max-priority` declaration — OQ4, declared exactly once at the re-create) |
| `/opt/poc` deploy root on the VMs | `/opt/ea` | V2 install paths (provisioned fresh by the V2 install scripts; the first organization's `/opt/poc` tree remains until the estate switch-over) |

## Deliberately unchanged

- The `poc` OS user on the VMs and `poc@…` SSH invocation: an estate
  identity, not a component name. Renaming a VM user is out of scope for
  the naming-family decision; revisit only if the owner directs it.
- `poc` strings inside prose that is *about* the first organization's
  stack (decision logs, coexistence attribution): allowed by the §9.7
  whitelist — the micro-gate grep treats these as live coexistence
  identifiers, not name references.

## Micro-gate status

- [x] Mapping table committed (this file).
- [x] Grep audit over V2-owned trees (`services/`, `schemas/`,
      V2 compose): **clean** — no pre-rename estate names in any V2-owned
      component (the V2 deploy layer does not yet exist; it will be born
      `ea-`-named).
      `schemas/message-v1.json` contains one `POC_TTL_DEFAULT` mention in
      prose describing the baseline build's M2 behavior — live coexistence
      identifier, retained.
- [x] **V2 deploy layer born ea-named — `deploy-v2/` created 2026-11-13** (owner
      chose `deploy-v2/` as the tree name): 33 files — m0 (rabbitmq/temporal
      composes, install.sh, hosts.env.example, tests) + m1 (topic-bridge) + m2
      (lifecycle/worker) + m5 (hindsight). Full ea- transform applied: repo-side
      paths repointed `deploy/mN` → `deploy-v2/mN`, broker user `poc:` → `ea:`,
      queue topology `ea-tasks`/`ea-tasks.dlq`/`ea-tasks.response` (durable,
      x-max-priority:3), labels `ea.task|ea.owner|ea.expires`, image
      `ea/executor-stub`, demo repo `ephemeral-v2-demo`, `/opt/ea` paths.
      Coexistence amendments: m0 §3/§4 reuse the first organization's live broker/Temporal
      containers when present; §1 no longer renames hostnames on
      already-provisioned VMs (owner-supplied estate hostnames kept — e.g.
      `vm-hermes-agent`); the `poc` OS user stays per the mapping table.
      m0 Tier-1 harness 9/9 PASS; all 5 service modules build+test green.
- [x] Registry re-tag **executed 2026-11-13** (build phase opened by owner):
      the registry-resident images re-tagged `ea/…:1.0.0`, digest-identical
      (3/3 OK — claude-coder, hermes-ephemeral, lifecycle; digests verified
      from manifest headers). Correction recorded: only 3 estate images were
      ever registry-resident; the other 6 of the originally listed 9 were
      built at install time without a registry push (so there is nothing
      to re-tag — the V2 install layer builds them `ea/`-named). The
      `rename-to-ea.sh` IMAGES list was corrected to match.
- [x] Queue re-creation **executed 2026-11-13**: `ea-tasks` declared durable
      with `x-max-priority: 3` (the single OQ4 declaration point); the
      stale `agent.tasks.dlq` (35 dead messages) deleted per plan. The first
      organization's `agent.tasks.*` queues remain untouched until the estate switch-over.
- [ ] The estate's baseline test path re-run green under `ea` names — deferred to
      the staged build (precondition: `ea-net` + V2 deploy layer installed,
      stages 1–2); affected structural assertions re-run before any new
      feature lands.
