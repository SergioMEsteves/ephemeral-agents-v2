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
