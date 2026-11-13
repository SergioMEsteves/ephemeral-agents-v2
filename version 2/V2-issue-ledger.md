# V2 issue ledger

> Per `V2-platform-design.md` §9.6: every V2 build issue, V1 format —
> symptom → wrong assumption → root cause → the rule now followed.
> One numbered entry per issue, appended in build order.

## 1. m0 netplan write produces an invalid file

- **Symptom:** `--apply-netplan` left `/etc/netplan/01-netcfg.yaml` with
  `unknown key 'version'` on the role VMs; network survives in memory but
  a reboot would orphan the VM.
- **Wrong assumption:** that the V1 install script's heredoc was
  copy-safe — it was never exercised on a clean VM during V1 (all VMs
  already had netplan configs when the baseline was captured).
- **Root cause:** the `install.sh` printf emitted a `version: 2` block
  without the `network:` root key.
- **Rule:** any script that writes a config file gets verified against a
  real parse (`netplan apply` / schema validation) in the same run, and
  the fix carries a byte-level check — display-rendered file contents
  are not evidence.

## 2. Temporal fell off `poc-net` on recreation (same class as the V1 rabbitmq lesson)

- **Symptom:** after the m0 apply, `m2-worker` / `topic-bridge` could not
  resolve `temporal` (embedded-DNS SERVFAIL); the estate's V1 path was
  down while every container showed `Up`.
- **Wrong assumption:** that declaring the external `poc-net` next to the
  implicit default network was enough.
- **Root cause (two independent bugs):** (a) V1 wired the shared network
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
  `.env` yet) while the V1-provisioned volume persisted. Owner decision
  taken 2026-11-13: preserve V1 credentials through the coexistence
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
  value does NOT match the live broker password (stale, V1-era) and the
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
  V1 backport `c2649a7` — 3 composes + 2 Go comments; the 3 `version 1/`
  docs were already parameterized). Verified byte-level: zero
  credential bytes remain in either repo's tracked files; runtime path
  unchanged (install scripts write `RABBITMQ_PASS` to gitignored
  `/opt/poc/deploy/m1|2/.env`, 0600).
