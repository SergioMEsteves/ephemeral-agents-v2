# V2 issue ledger

> Per `V2-platform-design.md` §9.6: every V2 build issue in the standard format —
> symptom → wrong assumption → root cause → the rule now followed.
> One numbered entry per issue, appended in build order.

## 1. m0 netplan write produces an invalid file

- **Symptom:** `--apply-netplan` left `/etc/netplan/01-netcfg.yaml` with
  `unknown key 'version'` on the role VMs; network survives in memory but
  a reboot would orphan the VM.
- **Wrong assumption:** that the install script's heredoc was
  copy-safe — it was never exercised on a clean VM in the baseline build
  (all VMs already had netplan configs when the baseline was captured).
- **Root cause:** the `install.sh` printf emitted a `version: 2` block
  without the `network:` root key.
- **Rule:** any script that writes a config file gets verified against a
  real parse (`netplan apply` / schema validation) in the same run, and
  the fix carries a byte-level check — display-rendered file contents
  are not evidence.

## 2. Temporal fell off `poc-net` on recreation (same class as the baseline rabbitmq lesson)

- **Symptom:** after the m0 apply, `m2-worker` / `topic-bridge` could not
  resolve `temporal` (embedded-DNS SERVFAIL); the estate's pre-rename path was
  down while every container showed `Up`.
- **Wrong assumption:** that declaring the external `poc-net` next to the
  implicit default network was enough.
- **Root cause (two independent bugs):** (a) the baseline build wired the shared network
  with a manual `docker network connect`, which every compose recreation
  silently drops; (b) a container attached to TWO networks with the same
  alias on both makes Docker's embedded DNS SERVFAIL peer lookups, so the
  compose also cannot just *add* the network — the services must live on
  `poc-net` only, aliases declared.
- **Rule:** shared-network membership is compose-declared, never
  attached by hand (rabbitmq already followed this; temporal now does
  too). The rabbitmq-pattern — services live ONLY on `poc-net`, aliases
  = service names — is the template for every multi-service stack in V2.

## 3. Credential regeneration vs persistent data volumes

- **Symptom:** after the m0 apply, Temporal failed with
  `pq: password authentication failed for user "temporal"` — the install
  minted a fresh `TEMPORAL_DB_PASS` while the existing
  `temporal-pg-data` volume still held the old credential.
- **Wrong assumption:** that `.env` generation is side-effect-free; the
  DB password lives in the data volume, not the env file.
- **Root cause:** m0's "generate if absent" ran on the fresh V2 tree (no
  `.env` yet) while the baseline-provisioned volume persisted. Owner decision
  taken 2026-11-13: preserve the estate's existing credentials through the coexistence
  period (rabbitmq pass reused; temporal aligned via socket-auth
  `ALTER USER` to the fresh V2 pass — the volume side is authoritative
  when old, the env file when new).
- **Rule:** before minting a credential a script must check for a
  persistent volume that outlives it; when it changes one side of a
  volume/env pair, it must align the other side and say so in its log.

## 4. Registry VM address drift after downtime

- **Symptom:** the registry VM became unreachable at its documented
  address; PVE showed it running; it had silently taken a new LAN
  address (DHCP lease move). Contemporaneous: the docker-registry-ui
  container was found absent entirely and had to be re-created from its
  compose.
- **Wrong assumption:** that the registry VM's address was stable.
- **Root cause:** no static netplan on the fourth VM and no ssh alias —
  it was never in the three-VM M0 matrix.
- **Rule:** all four VMs get static netplan + ssh alias at S0; a
  reboot-and-reach test is the verification event (S0 close-out).
- **Closed 2026-11-13:** owner granted passwordless sudo on the registry VM;
  static pin applied (192.0.2.13/24, gw .1), DHCP installer config removed
  so it can no longer race the pin; verified by reboot-and-reach —
  ssh alias, registry API 200, UI 200, catalog intact (8 repos incl. ea/…).

## 5. Literal broker password tracked in the m1/m2 composes (sweep miss)

- **Symptom:** during the S4 deploy-v2 wiring review, the m1/m2 composes
  were found to carry a literal 16-char broker password in
  `RABBITMQ_URL` — despite the adjacent comment claiming the password is
  interpolated from `.env`. Byte-level verification showed the tracked
  value does NOT match the live broker password (stale, pre-rename) and the
  live value is only in gitignored `.env` files — so no burn and no
  rotation required, but the disclosure still violates de-identification.
- **Wrong assumption (two layers):** (a) the de-identification sweep
  (2026-11-10) verified "zero credentials" — it checked a credential
  pattern that did not match this URL-embedded form, and (b) every
  subsequent read of the compose files showed `***` — the terminal
  masking convention made the literal look like a placeholder, so it
  passed unnoticed through m0, the rename, and the S4 wiring review.
- **Root cause:** the m5 compose got the `${RABBITMQ_PASS}` treatment
  during de-identification but m1/m2 only got the comment claiming it;
  the display masking then hid the literal from every read.
- **Rule (two):** the credential sweep must include URL-embedded
  credentials (`amqp://user:PASS@`), byte-level, not display-level; and
  a comment claiming interpolation must be backed by a byte-level check
  that the literal is absent — comments are not evidence.
- **Fixed 2026-11-13:** m1/m2/m5 composes now interpolate
  `${RABBITMQ_PASS:?set RABBITMQ_PASS in .env}` (V2 commit `0734c57`;
  the same fix was applied to the pre-rename tree — 3 composes + 2 Go
  comments — before the reorganization removed those files). Verified
  byte-level: zero credential bytes remain in this repo's tracked files;
  runtime path unchanged (install scripts write `RABBITMQ_PASS` to
  gitignored `.env` files, 0600).
## 6. m1 bridge could not consume `ea-tasks` (PRECONDITION_FAILED)

- **Symptom:** the m1 gate failed at T1 — zero messages consumed; the
  topic-bridge logged `PRECONDITION_FAILED: inequivalent arg 'x-max-priority'`.
- **Wrong assumption:** that `ea-tasks`' `x-max-priority: 3` declaration
  (the single OQ4 declaration point) did not need to be mirrored in the
  consumer's own queue declare.
- **Root cause:** `topic-bridge/cmd/adapter/main.go` declared the queue
  without `x-max-priority`; RabbitMQ rejects inequivalent re-declares.
- **Rule:** every queue-declare site must byte-match the canonical
  declaration (`x-max-priority: 3` on the `ea-*` task queues); a
  queue-shape constant lives in one place per service.

## 7. m2 gate ran the wrong executor (compose carried a future default)

- **Symptom:** the first m2 gate run failed V1/V5 — real hermes executors
  spawned, exited 2 with unstaged m3 env.
- **Wrong assumption:** that the m2 compose could carry the M5-era
  `EA_EXECUTOR_DEFAULT: hermes` for forward-compatibility.
- **Root cause:** the compose-evolution rule was violated — the m2-era
  compose must be stub-only (the M3 install writes the executor switch).
- **Rule:** a milestone's compose carries only that milestone's config;
  future-era settings land in the milestone that owns them.

## 8. m4 hindsight compose took over the first organization's stack

- **Symptom:** deploying the m4 hindsight stack replaced the first organization's containers
  and reused its data volume — the first organization's memory system was down.
- **Wrong assumption:** that compose project names and volume names
  inherited from the baseline build were safe.
- **Root cause:** the m4 compose kept the first organization's project name `hindsight` and
  volume name.
- **Rule:** every V2 compose sets `name: ea-*`, `ea-*` containers, and an
  own volume; the restoration sequence (first organization up, V2 up) is part of the fix
  runbook, not an afterthought.

## 9. m5's committed fix never existed — gitignore masked whole source trees

- **Symptom:** `ea/manager:1.0.0` rebuilt from the committed code did not
  compile (`undefined: EnvTasksQueue`), and the queue-direct fix was
  absent from the commit that claimed it (`c4e1282`).
- **Wrong assumption:** that a `git add services/manager` had committed
  the source — the `.gitignore` binary patterns (`services/**/manager`,
  `services/**/gateway`, `services/**/adapter`) masked the *entire*
  source directories, so the sources were silently untracked.
- **Root cause:** ignore patterns intended for compiled binaries also
  matched the directories holding the sources; `git status` showed a
  clean tree, so nothing looked wrong.
- **Rule:** ignore patterns that hide a directory must carry explicit
  negations for the source tree, verified by `git check-ignore` on every
  file the milestone claims to commit; "clean tree" is not evidence of
  tracked sources.

## 10. queue-direct publish used the capability as the routing key

- **Symptom:** with `TASKS_EXCHANGE` unset, the manager published to the
  default exchange with the agent-capability string as the routing key —
  silently unrouted (messages vanish, no error).
- **Wrong assumption:** that clearing the exchange alone was the fix.
- **Root cause:** the publish call site kept the capability routing key;
  against the default exchange the routing key must be the queue name.
- **Rule:** publish-mode constants (exchange, routing key) must change
  together and carry a test that asserts the effective routing target.

## 11. §5 injections silently exercised the stub executor

- **Symptom:** the GitHub-block injections (F1/F2) "succeeded" — with the
  block provably loaded and verified live, failure-shaped reports never
  appeared.
- **Wrong assumption:** that the §4 E2E's hermes-path success implied the
  §5 injections used hermes too — the lifecycle's `EA_EXECUTOR_DEFAULT`
  was unset, so the executor resolved to the `EA_IMAGE` stub pin.
- **Root cause:** the M5-era executor switch (`EA_EXECUTOR_DEFAULT:
  hermes`) documented in m3's compose-evolution comment was never
  implemented by the m5 install, and the M5_FROM=5 stage gate skipped the
  §1–§2 stages that would have applied it.
- **Rule:** every stage-gated run re-asserts the executor default (§2' in
  m5/install.sh) and hard-fails if it is not applied; a test that depends
  on which executor runs asserts that executor by name.

## 12. §5 runbook was stub-era (five defects)

- **Symptom:** injections published rejected tasks (`"dev"` is not a real
  catalog capability), waited 45 s for ~13-min hermes reports, killed
  nothing (`pkill` matches names, not PIDs), and blocked the wrong path
  (nft `output` hook — container egress traverses `forward`).
- **Wrong assumption:** that the pre-rename runbook mechanics survived the
  executor change.
- **Root cause:** the runbook was never re-derived against real executors.
- **Rule:** every wait is a poll on the observable (report file),
  kill-by-PID with a docker-kill fallback, fault injection blocks the
  path the fault requires (forward hook), and the injected capability is
  a real catalog ref.

## 13. §6 token check aborted on an undefined variable and raced revocation

- **Symptom:** the §6 hardening run died silently between "issued token
  200" and the revoke step (`tok: unbound variable` under `set -u`);
  an earlier run's immediate post-revoke check read 200.
- **Wrong assumption:** that the post-revoke check used the variable the
  pre-revoke check used (`$src`), and that revocation is instant.
- **Root cause:** the post-revoke curl referenced an undefined `$tok`;
  GitHub revocation propagates within seconds.
- **Rule:** both halves of a lifecycle check read the same variable; a
  revocation check sleeps past propagation (5 s) before asserting.

## 14. M1 build-start security items not yet built (proxy caller-auth, hindsight token classes)

- **Symptom (build-time finding, 2026-11-15):** preparing the CoS deployment
  surfaced that two §9.1 build-start security dependencies the CoS credential
  contract assumes were never built in the staged run: the llm-proxy still
  forwards with the caller's own key and no per-class tokens (v3 sanitize
  only), and the built ea-hindsight has no CoS-write/executor-read token
  classes (auth.go was in the impact inventory, not in the build).
- **Wrong assumption:** that "build-start security items" from §9.1 were all
  executed at S0/S1 — only registry TLS + basic-auth landed.
- **Root cause:** the security stage list was treated as complete at S1;
  nothing re-checked the remaining §9.1 items before M1.
- **Rule:** a milestone's install preconditions include every §9.1 item it
  names — re-verified at the milestone, not assumed from earlier stages.
- **Disposition:** credentials staged (m1-cos/stage-credentials.sh, values
  never printed); the proxy caller-auth + hindsight token-class enforcement
  land as part of the M1 completion (or the A+ gate, which asserts the
  capability check) — tracked as M1 build items, not closed defects.

## 15. Owner amendment — the CoS holds an OpenRouter key directly

- **Symptom:** the CoS gateway's model list did not include the OpenRouter
  catalog — by design: the CoS was wired to the llm-proxy's anthropic-compat
  path, which exposes only the translated model shape.
- **Decision (owner, 2026-11-15):** the owner asked to configure OpenRouter
  and the API key on the ea-cos gateway directly. Amends the M1 §5 credential
  contract: the CoS profile env now carries `OPENROUTER_API_KEY`
  (the owner's OpenRouter key, staged from the single m3.env source, value
  never displayed) + `MODEL_DEFAULT: z-ai/glm-5.3-flash`.
- **Consequence:** the "highest-spend actor inside the proxy perimeter"
  property is suspended for the CoS until the key is re-centralized — the
  proxy remains the executor path unchanged. Tracked for the A+/hardening
  pass: restore the proxy-perimeter property (proxy model-list passthrough
  or per-class token), or accept the CoS as a key-holder permanently.
- **Rule:** credential-contract changes are owner decisions recorded in this
  ledger with their A+ follow-up named.

## 16. New private project repos cannot be cloned from VM-Xa (no repo credential)

- **Symptom (owner, 2026-11-15):** creating a new project + GitHub repo,
  cloning it on VM-Xa fails on permissions — the estate deliberately built
  VM-Xa credential-free for GitHub.
- **Wrong assumption:** that the "no GitHub token" contract line could stand
  while the architecture gives VM-Xa two legitimate repo needs: the CoS's
  workspace IS the project repo checkout (M1 §4, repo as source of truth),
  and executors clone project repos per task.
- **Root cause:** the credential contract predated the repo-as-workspace
  reality (the same tension D12 resolved for state; new private repos made
  it concrete).
- **Fix (owner-approved, 2026-11-15):** the CoS holds a **scoped READ-ONLY**
  fine-grained PAT (Contents: Read, project repos) staged as a git
  credential file (0600, mounted read-only, value never printed) — the
  contract line becomes "no WRITE token, repo-read scoped". Executors keep
  the designed mechanism unchanged: per-run GitHub App installation tokens
  minted at spawn, revoked at reap.
- **New-project checklist (owner, per project):** create the repo → install
  the `ephemeral-agents-poc` GitHub App on it (1 min) → done: the CoS clone
  is covered by the scoped PAT, executor credentials mint per task.
- **Rule:** contract denials are re-examined whenever an architecture
  decision gives a component a new legitimate resource need.

