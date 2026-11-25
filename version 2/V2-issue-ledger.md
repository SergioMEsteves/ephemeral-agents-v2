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

## 17. Docker layer cache shipped a stale base package (needrestart CVE)

- **Symptom:** M5 §6 trivy failed `ea/lifecycle:1.0.0` on one fixable HIGH (CVE-2026-124757, needrestart LPE, fixed in 3.11-1.1~deb13u1) — after an image "rebuild".
- **Root cause:** the Dockerfile's `apt-get update && apt-get -y upgrade` layer was cache-hit from the 2026-11-19 build; a cached RUN layer's apt snapshot is frozen. Wrong assumption: a rebuild re-fetches packages.
- **Fix:** `--no-cache` rebuild of ea/lifecycle + ea/worker, push to the registry, redeploy. Image eb040562cd74 (2026-11-22) scans clean 9/9.
- **Rule:** a CVE-remediation rebuild must bust the base-image layer cache; a cached rebuild changes nothing.

## 18. Privilege-path mismatch aborted the token-lifecycle gate silently

- **Symptom:** M5 §6 exited with no message right after "issued token -> HTTP 200" — the revoke step never logged.
- **Root cause:** the §6 issuance runs under `sudo` (token state file `/tmp/ea-issue-token-last` written root-owned); the `--revoke-last` step ran as `poc`, could not read the root-owned state file, and `set -euo pipefail` killed the run. Wrong assumption: the two steps of one gate share an execution context.
- **Fix:** both steps now run the same `sudo bash -c` path in `deploy-v2/m5/install.sh` §6. Re-run: issue→200→revoke→401 green.
- **Rule:** gate steps that share state must share a privilege path; a state file written by one user is unreadable to another.

## 19. Staging overwrote the CoS credential file — the recreated CoS lost its auth

- **Symptom:** after the 2026-11-22 m5 live-estate runs, `ea-m5-cos` came back up with blank `GATEWAY_SESSION_TOKEN`/`HERMES_DASHBOARD_SESSION_TOKEN` and crash-looped on the public-dashboard auth guard; the Desktop's `ea-cos` connection 401'd against a rotated token.
- **Root cause:** §1 stages `deploy-v2/m5/.env` to VM-Xa with `cat >` — a full overwrite from a local copy that carries only the keys §1 knows (rabbitmq pass, repo, hosts). The four CoS allow-list vars minted by `m1-cos/stage-credentials.sh` were silently dropped, and the next compose recreate rebuilt the container without them. Wrong assumption: the staged .env is a superset of what the compose file interpolates.
- **Fix:** §1 now stages to `.env.staged`, merges (staged values win, existing keys preserved), then runs `stage-credentials.sh` remotely to re-add any missing allow-list key. Recovery performed live: four vars re-minted on VM-Xa, `cos` recreated, model-info 200 with the new token; the Desktop's stored token updated.
- **Rule:** a staged config file must be merged, not overwritten — the staging script's key set is not the deploy's key set; anything minted by a later stage belongs to the file's lifetime, not the run's.

## 20. The durable mount existed; the state didn't use it

- **Symptom:** TP-M1-COS TC-4 — the CoS kanban board and session state (D12's "reboot-durable state store of record") lived in the container filesystem; `/opt/ea/cos/state` was empty while `/root/.hermes` inside the container held everything, and a container recreate (which the 2026-11-22 recovery actually performed) wiped the board.
- **Root cause:** the compose mounted `/state` and the entrypoint's comment claimed "the board state lives in /state (D12)", but nothing told the Hermes profile to use it — `HERMES_HOME` was unset, so the profile defaulted to `~/.hermes`. Wrong assumption: a bind mount is a location, not a pointer — state goes where HOME says, not where a volume exists.
- **Fix:** `HERMES_HOME=/state` in the cos compose env; the entrypoint's profile paths became `$HERMES_HOME`-relative; live migration of the 2.9 GB profile state (`docker cp` snapshot → recreate → restore) with zero data loss; profile verified at `/state/profiles/cos` post-recreate.
- **Rule:** every reboot-durability claim must name the exact mechanism AND the env/flag that activates it, asserted by the compose file — "we mounted a volume" is not durability.

## 21. A live token's recognizable prefix/suffix published in an evidence snippet

- **Symptom:** the M4 wiring snippet (`deploy-v2/m4/evidence/m4-wiring-snippet.env`) recorded `LLM_WIKI_READ_TOKEN=gho_<redacted>` — the first 7 and last 4 characters of the workstation's **currently live** GitHub OAuth token.
- **Root cause:** the masking convention ("show first+last") is right for chat, wrong for artifacts — a mask short enough to keep typing-friendly keeps enough to identify the credential and defeats later rotation audits. Wrong assumption: a masked value is a redacted value.
- **Fix:** the snippet now carries `gho_<redacted>`; the fragments were scrubbed from full history via a second `git filter-repo` pass before the token fragments could circulate. Rotation optional: a 7+4-character fragment of a ~40-char token is not usable; recorded as an accepted residual with the option to rotate the workstation token out of caution.
- **Rule:** masks live in conversation, never in artifacts — artifacts carry `<redacted>` or nothing; "enough to recognize" is enough to leak.

## 22. llm-proxy: standalone container with no deploy-tree home, lost at reboot (2026-11-24, during H1a)

- **Symptom:** the CoS's model endpoint (`BROKER_HOST:9999`) was dead — nothing listened on 9999 on the execution VM; `docker start llm-proxy` (the restart-stack fallback) referenced a nonexistent container. Found during H1a's pre-check battery; not caused by the firewall change.
- **Root cause:** llm-proxy was created as a bare `docker run` during M3 — no compose service, no systemd unit anywhere in the deploy layer. The staged source is in-repo (`deploy-v2/m3/llm-proxy/proxy.js`, ledger L3), but the *container* was never recoverable from the record; the 2026-11-22 reboot lost it and nothing noticed (CoS `:8084/model/info` returns config without calling the model, so health checks passed).
- **Fix applied:** container recreated faithfully from the repo-staged source (md5-verified identical), `ea-net` alias `llm-proxy`, published :9999, `--restart unless-stopped`; CoS path verified Xa→Xb:9999 `/hello` → 200.
- **Rule:** a service the architecture depends on must exist in the deploy tree (compose or unit), not just in a shell history — "restart if present" (`restart-stack.sh`'s `$E start llm-proxy || true`) is not a recovery path for a service with no creation record. Follow-up: move llm-proxy into the deploy tree with its own compose definition and a health-check line (open item, candidate for the H2 session).

## 23. Podman executor egress is enforced empirically but not by a pinned ruleset (2026-11-25, during H1b)

- **Symptom:** after H1b, executor traffic leaves via pasta (`--network pasta:-o,192.168.0.250`), which iptables classifies as **host-originated** — Docker's `DOCKER-USER` chain (H1a's enforcement point) never sees it. The H1a ruleset remains installed but governs only a Docker-era rollback path, not the live podman path.
- **Verified empirically (probe battery, `deploy-v2/h1/evidence/podman-egress-probe.txt`):** gateway VM :8083 BLOCKED (000), registry :5000 OPEN (400 = answering), github :443 OPEN (200) — the H1a policy's intent holds in practice under pasta, today.
- **Residual:** the enforcement path under podman is not pinned by configuration — it currently depends on incidental host rules, and nothing asserts it in a gate. A future ufw/netplan/pasta change could silently re-open LAN lateral movement (the exact class H1a closed for Docker). Wrong assumption to record: "the H1a firewall covers executors" — it covered Docker-bridge traffic only.
- **Required fix (follow-up):** a formal podman-path egress ruleset (nftables/ufw rules for pasta-originated uid-1001 traffic, or pasta-native options), plus a gate assertion re-running the H1a connectivity battery against a podman-spawned executor. Acceptance = the H1a 12-point battery passes identically under the podman path, asserted by an idempotent script + unit, the way `ea-egress-firewall.service` does for Docker.
- **Rule:** a security property is only held where it is enforced AND asserted; an empirical probe is evidence for one moment, not a mechanism.
