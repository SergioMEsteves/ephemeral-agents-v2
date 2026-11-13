# V1 → V2 name mapping (ea- rename)

> Recorded at the opening of the V2 build phase per
> `V2-platform-design.md` §1 and the rename micro-gate (§9.7).
> Scope note: the baseline-synced `deploy/` tree keeps its V1 names — it is
> verbatim V1 evidence and renaming it silently would break traceability to
> the signed M0–M5 gate runs. Every V2-owned component created from here on
> uses the `ea-` family from birth; nothing in V2-owned code re-defines
> these mappings.

| V1 name | V2 name | Applies to |
|---|---|---|
| `poc-net` (docker network) | `ea-net` | V2 compose layer |
| `poc/hermes-ephemeral:1.0.0` (image) | `ea/hermes-ephemeral` | executor image (re-tag, digest-identical) |
| `poc/claude-coder:1.0.0` (image) | `ea/claude-coder` | executor image (re-tag, digest-identical) |
| `poc/{topic-bridge,lifecycle,worker,executor-stub,hindsight-api,gateway,manager}` (image repos) | `ea/{…}` | the other 7 deployed images (re-tag, digest-identical) |
| `POC_*` env vars (`POC_NETWORK`, `POC_EXECUTOR_DEFAULT`, `POC_IMAGE_HERMES`, `POC_IMAGE_CODER`, `POC_IMAGE_DEFAULT`, `POC_IMAGE`, `POC_TTL_DEFAULT`, `POC_CIDR`, `POC_REGISTRY`, `POC_DOCKER_DEBUG`) | `EA_*` (same suffixes) | V2 services + compose env wiring |
| `poc-*` container / queue names | `ea-*` | V2 compose service names; RabbitMQ queues (queues re-created once under `ea-*` with the `x-max-priority` declaration — OQ4, declared exactly once at the re-create) |
| `/opt/poc` deploy root on the VMs | `/opt/ea` | V2 install paths (provisioned fresh by the V2 install scripts; V1's `/opt/poc` tree remains until the estate switch-over) |

## Deliberately unchanged

- The `poc` OS user on the VMs and `poc@…` SSH invocation: an estate
  identity, not a component name. Renaming a VM user is out of scope for
  the naming-family decision; revisit only if the owner directs it.
- `poc` strings inside prose that is *about* the V1 POC (decision logs,
  provenance citations): allowed by the §9.7 whitelist — the micro-gate
  grep treats these as provenance citations, not name references.

## Micro-gate status

- [x] Mapping table committed (this file).
- [x] Grep audit over V2-owned trees (`services/`, `schemas/`,
      V2 compose): **clean** — no V1 names in any V2-owned component
      (the V2 deploy layer does not yet exist; it will be born `ea-`-named).
      `schemas/message-v1.json` contains one `POC_TTL_DEFAULT` mention in
      prose describing V1 M2 behavior — provenance citation, retained.
- [x] Registry re-tag **executed 2026-11-13** (build phase opened by owner):
      the registry-resident images re-tagged `ea/…:1.0.0`, digest-identical
      (3/3 OK — claude-coder, hermes-ephemeral, lifecycle; digests verified
      from manifest headers). Correction recorded: only 3 V1 images were
      ever registry-resident; the other 6 of the originally listed 9 were
      built at V1 install time without a registry push (so there is nothing
      to re-tag — the V2 install layer builds them `ea/`-named). The
      `rename-to-ea.sh` IMAGES list was corrected to match.
- [x] Queue re-creation **executed 2026-11-13**: `ea-tasks` declared durable
      with `x-max-priority: 3` (the single OQ4 declaration point); the
      stale `agent.tasks.dlq` (35 dead V1 messages) deleted per plan. V1
      `agent.tasks.*` queues remain untouched until the estate switch-over.
- [ ] V1 baseline test path re-run green under `ea` names — deferred to
      the staged build (precondition: `ea-net` + V2 deploy layer installed,
      stages 1–2); affected structural assertions re-run before any new
      feature lands.
