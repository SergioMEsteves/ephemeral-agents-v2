# V2 Offboard Runbook — retiring a project, reusing the estate

> The executable checklist behind book Chapter 16 §16.6. Read the chapter
> for the why; run this for the how. Host addresses are placeholders —
> `deploy-v2/m0/hosts.env` is the single source of truth. Every step's
> verification line is the gate for the next step; do not run ahead.

## Step 0 — decide the path

- **Path A — CoS reset** (~10 min): same estate, same project repo, fresh
  work slate. Use when the repo/topology stay and only the work changes.
- **Path B — estate reclone** (minutes after freeze): different repo, full
  identity reset. Use for a brand-new project. Requires `vm-xlg-built`
  (freeze §16.3 done); if not frozen, freeze first or budget a full rebuild.

Both paths start with Step 1–2. Path A then stops; Path B continues.

## Step 1 — drain in-flight work

- [ ] No task workflows running: check Temporal UI (`http://<vm-xb>:8080`)
      or `temporal workflow list` — zero open `TaskWorkflow`.
- [ ] Worker queue drained: `rabbitmqctl list_queues` (via SSH to vm-xb)
      — `ea-tasks` depth 0.
- [ ] Survivor check: `docker ps --filter label=ea.owner=lifecycle` on
      vm-xb — empty. Zero survivors (the reaper's normal close-out).

## Step 2 — bring the front-of-house down

- [ ] On VM-Xa: `cd /opt/ea/deploy-v2/m5 && docker compose down`
      (ea-m5-gateway, ea-m5-manager, ea-m5-cos stop; volumes kept).
- [ ] Verify: `docker ps | grep ea-m5` — empty; gateway :8083 refuses.

## Path A — CoS reset (steps 3A–6A)

### 3A — clear the project's memory of itself (the step deletes miss)

- [ ] On VM-Xa: empty `/opt/ea/cos/state/` (board + session state) and
      `/opt/ea/repos/` (task working clones). The container is stateless;
      its mounts are not — clear them explicitly.
- [ ] Verify: both directories list empty.

### 4A — archive, then clear the tracker and board mirror

- [ ] Tier-1 tracker (GitHub Issues project): export/archive what the
      audit trail needs (archive, do not delete).
- [ ] CoS board: export per the board backup rule if the audit needs it.

### 5A — re-mint and re-register

- [ ] Remint the CoS session token on VM-Xa (same mint as install §6).
- [ ] Delete the old Desktop connection entry (Settings → Gateways); add a
      fresh named one with the new token (Special 4's seven steps). Never
      reuse the old token — a credential minted for project N must never
      authenticate project N+1.
- [ ] Verify reconnect survives a VM reboot (the D12/desktop assertion).

### 6A — point at the new work

- [ ] New manifest/persona/roster context if the *project definition*
      changed (else the same profile is correct — it is read-only and
      repo-agnostic).
- [ ] Hindsight: delete the old scope rows on the memory VM
      (`ea-hindsight-pg` — scope-keyed; scoping is a convention today, so
      delete explicitly). Verify the new project's scope key starts empty.
- [ ] Smoke: one trivial approved task end-to-end; report lands; zero
      survivors; token revoked. Record in the decision log.

## Path B — estate reclone (continues after Step 2)

### 3B — confirm the archive before touching any VM

- [ ] The project repo is fully pushed: decision log, issue ledger,
      TP/evidence packs, findings report — the repo IS the archive.
- [ ] Board/tracker exported per Step 4A. Nothing of value lives only on
      a VM disk.

### 4B — reclone the four VMs

- [ ] From `vm-xlg-built` (or `ubuntu-24-ea-base` if the build changed):
      four clones, re-pin IPs/hostnames via the new `inputs.yaml` →
      `render-inputs.py --render` → `hosts.env`.
- [ ] Verify each clone's MAC↔VMID↔IP mapping before booting the batch
      (the pinning rule: verify by MAC, never by pinning order).

### 5B — re-mint everything, bring up, gate

- [ ] Credentials minted fresh on the new estate: registry CA + bcrypt,
      broker password, Hindsight tokens, CoS session token, provider key.
      Nothing inherited (the spin-up rule, Chapter 16 §16.4).
- [ ] Compose bring-up in dependency order; gates re-run as the
      acceptance test (install check-only → full run).
- [ ] Verify the silence: no token-shaped strings from the old project
      anywhere on the new estate.

### 6B — register the new project

- [ ] New repo (source of truth), project manifest, roster persona,
      Desktop connection (new name + fresh token), GitHub App
      installation on the new repo (~1 min), new tracker project, new
      Hindsight scope key.
- [ ] Smoke: one trivial approved task end-to-end; report lands; zero
      survivors; token revoked.

### 7B — record

- [ ] Decision-log entry: retired project id, offboard date, archive
      location (repo + tracker), path taken (A/B), reclone template.
- [ ] Onboarding recorded per `RUNBOOK-V2-NEW-PROJECT.md`.

## Rollback notes

- Path A is reversible until 3A (bring the stack back up — state intact).
  After 3A the old session state is gone by design; work is in the repo.
- Path B keeps the old VMs until the new estate gates green (clone-first,
  retire-second). Do not wipe originals before the new estate passes its
  smoke test.

## The re-mint rule (never relaxed)

A credential minted for project N must never authenticate project N+1.
If a step needs a value from the old estate, it is a value that should
have been exported to the repo — stop and export it, don't carry the
secret forward.
