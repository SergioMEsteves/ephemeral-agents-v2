# TP-H1a — Executor Egress Allow-List (D-APlus-egress)

**Signed:** 2026-11-24 (by Hermes Agent on the owner's standing sign-off authorization, all assertions PASS with evidence)
**Change:** static executor-bridge egress policy in the Docker `DOCKER-USER` chain on the execution VM, implemented as `/usr/local/bin/ea-egress-firewall.sh` + `ea-egress-firewall.service` (enabled, oneshot after docker). Allow-list: intra-`ea-net`, registry :5000, Hindsight :8082, llm-proxy :9999 (host-IP rule, belt-and-braces), internet TCP 80/443. Everything else from the ea-net subnet drops (LAN lateral movement, other VMs, PVE host, router). DNS is Docker-embedded (host-side) and unaffected.

## Gate results

| # | Assertion | Result | Evidence |
|---|---|---|---|
| 1 | Positive: Hindsight :8082 reachable from ea-net container | PASS | `egress-ruleset.txt` battery (OPEN) |
| 2 | Positive: registry :5000 reachable | PASS | battery (OPEN) |
| 3 | Positive: GitHub/internet 443 reachable (git clone/push, model API) | PASS | battery (OPEN) |
| 4 | Negative: gateway VM :8083 NOT reachable | PASS | battery (BLOCKED) |
| 5 | Negative: PVE host :22 NOT reachable | PASS | battery (BLOCKED) |
| 6 | Negative: router :80 NOT reachable | PASS | battery (BLOCKED) |
| 7 | Negative: broker host-IP :5672 NOT reachable from containers | PASS | battery (BLOCKED) |
| 8 | Negative: ssh to VM-Xa NOT reachable | PASS | battery (BLOCKED) |
| 9 | Live e2e under the policy: gateway→manager→queue→executor→report, `status: success` | PASS | `e2e-report.json` (task `8c4ca0fd-2201-4a2d-957c-c6bcbb727455`, 2026-11-24T18:12:52Z) |
| 10 | Persistence: unit enabled; rules re-apply on boot after docker | PASS | `systemctl is-enabled` = enabled; idempotent insert script |
| 11 | No in-flight work at apply time; zero task-container survivors after | PASS | queues empty pre-change (ea-tasks 0); reaper exit-0, no task containers remaining |

## Notes recorded at execution

* **llm-proxy was found down** (standalone container lost — likely at the 2026-11-22 reboot; `docker start llm-proxy` referenced a nonexistent container). Recreated faithfully: bind-mount of the repo-staged source (`/opt/ea/llm-proxy/proxy.js`, md5-identical to `deploy-v2/m3/llm-proxy/proxy.js` per ledger L3), `ea-net` alias `llm-proxy`, published :9999, `--restart unless-stopped`. CoS path verified: Xa→Xb:9999 `/hello` → 200 `{}`. **Ledger-worthy:** the proxy was a bare `docker run` with no compose/unit anywhere in the deploy layer — it can be lost again at any host rebuild. Follow-up: give it a home in the deploy tree (H2 session or a standalone ledger fix).
* Executors' `ANTHROPIC_BASE_URL` in the live m3.env is `https://openrouter.ai/api` directly (not the proxy); the llm-proxy :9999 path is the CoS-class route. The host-IP :9999 rule is retained for contract completeness; executors do not traverse it.
* Firewall root-cause note for the ledger class: ufw's `deny (routed)` and Docker's DOCKER-USER chain coexist; container→host-IP traffic traverses INPUT (ufw), not DOCKER-USER — the host-IP rule is thus only effective for forwarded paths. The alias path (intra-bridge) is the operative one for executors.
* Script insertion-order bug (DROP first) was introduced and caught during bring-up; final ruleset verified in correct order before any task ran (no task was in-flight during the wrong-order window).
