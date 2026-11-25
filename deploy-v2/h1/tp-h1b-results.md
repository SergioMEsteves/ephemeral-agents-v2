# TP-H1b — Rootless Podman on the Execution VM (D-APlus-podman)

**Signed:** 2026-11-25 (by Hermes Agent on the owner's standing sign-off authorization, all assertions PASS with evidence)
**Change:** the execution VM's (vm-xb) full workload path now runs rootless Podman as the `poc` user — compose stacks (m0/m1/m2 era + worker + lifecycle), RabbitMQ, Temporal, and the executor spawn path (docker CLI → the poc user's podman.sock, docker-compat API; spawn network pinned `pasta:-o,192.168.0.250`). No Docker workloads remain on vm-xb (`docker ps` empty; podman info Rootless=true). Other VMs unchanged (Docker). Engine choice carried by `inputs.yaml config.engine: podman` → `hosts.env`.

## Root-cause fix landed during this gate

Every executor spawn initially died exit-254 (~16 s, empty artifact log). Root cause, proven by payload bisection: podman 5.7.0's **Docker-compat API maps an explicit `HostConfig.PidsLimit: 0` (always sent by the docker CLI) to cgroup `pids.max=1`** — the container could run exactly one process, so bash hit endless `fork: Resource temporarily unavailable`. Omitting the field yields the normal 2048; identical args via the podman CLI work — which is why manual replays passed while every lifecycle spawn failed.

Fix (commit `374b821`): the lifecycle spawn emits an explicit `--pids-limit` (default 512, `EA_PIDS_LIMIT`), making the pids budget a pinned safety property. Deployment note recorded: `podman load` registers images as `docker.io/ea/...` while compose pins `localhost/ea/...` — retag before recreate or the old image keeps serving.

## Gate results

| # | Assertion | Result | Evidence |
|---|---|---|---|
| 1 | Full M2 V-suite green under podman: V1 clean, V2 failure-surface, V3 TTL-timeout | PASS | `m2-podman-vsuite.txt` (V1/V2/V3 PASS) |
| 2 | V4 crash recovery (load-bearing): worker killed mid-task; independent reaper reaps at TTL; zero survivors | PASS | `m2-podman-vsuite.txt` (reaper got t004, zero survivors) |
| 3 | V5 mixed-10 (5 success / 3 failure / 2 timeout) all events logged | PASS | `m2-podman-vsuite.txt` (10/10 PASS) |
| 4 | V5 zero-survivors after the suite | PASS | survivors=0 |
| 5 | Live e2e gateway→manager→queue→executor→report under podman, exit-0 | PASS | `e2e-report-podman.json` (task `af4489c5`, 2026-11-25T02:25Z) |
| 6 | Rootless: executors run as uid 1001, no root daemon in the executor path | PASS | `podman info Rootless=true`; docker ps empty |
| 7 | Egress policy effective for podman executors (positive + negative probes) | PASS (sampled) | `podman-egress-probe.txt`: gateway VM :8083 BLOCKED (000); registry :5000 OPEN (400); github :443 OPEN (200) |
| 8 | Spawn reproducibility: full DOCKER_RUN env replayed manually under podman | PASS | exit 0, report.json written |

## Notes recorded at execution

* **Egress mechanism under podman is NOT the Docker `DOCKER-USER` chain** — pasta traffic is host-originated from iptables' view. Empirically the H1a policy intent still holds (LAN lateral blocked, registry/Hindsight/internet-80/443 open), but the enforcement path under podman should be formally documented and pinned (nftables/ufw rules for the podman path) in a follow-up ledger entry. The H1a script remains for any Docker-era rollback.
* The hermes-ephemeral entrypoint's contract is boot + hydrate + self-report + report.json + exit 0 (no agent loop) — `status: success` is the correct full behavior for this executor; branch-pushing work is the coder-executor path and out of scope for this gate.
* The m2 install gate-test Temporal drain lines were converted from `docker exec` to the `xb_engine` prefix (commit this run) — podman-only VM has no docker CLI.
* One manual-replay container (owner=lifecycle label from Hermes' own diagnostics) was removed before the zero-survivors assertion; the system's own runs left none.
