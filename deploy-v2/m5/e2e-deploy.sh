#!/usr/bin/env bash
# =============================================================================
# M5 — ordered full-stack bring-up (stage-gated S1–S7)
# =============================================================================
# Implements the M5 §3 end-to-end deploy flow (see deploy-v2/RUNBOOK-V2-BUILD.md).
# Idempotent; each stage's healthcheck must pass before the next; any failure
# halts + prints the failing stage (which names the owning milestone's gate
# test — recovery never means re-running the chain).
#
# Usage: bash deploy-v2/m5/e2e-deploy.sh
# Env: VM_XA VM_XB VM_HINDSIGHT (ssh aliases), ASSUME_YES=1 for non-interactive
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# hosts.env is the canonical host map — auto-load it if present (it also
# carries ENGINE, the container-engine choice: podman = rootless Podman on
# the execution VM, run as the poc user).
if [ -f "$REPO_ROOT/deploy-v2/m0/hosts.env" ]; then set -a; . "$REPO_ROOT/deploy-v2/m0/hosts.env"; set +a; fi
VM_XA="${VM_XA:-vm-xa}"; VM_XB="${VM_XB:-vm-xb}"; VM_HINDSIGHT="${VM_HINDSIGHT:-vm-hindsight}"
ENGINE="${ENGINE:-docker}"
# xb_engine — container-engine command prefix for vm-xb remote commands
# (rootless podman runs as the poc user; the remote shell resolves $(id -u poc)).
xb_engine() {
  if [ "$ENGINE" = "podman" ]; then
    echo 'sudo -u poc env XDG_RUNTIME_DIR=/run/user/$(id -u poc) podman'
  else
    echo docker
  fi
}
FAILED_STAGE=""

stage() { # stage <name> <cmd...> — run; on failure halt with the stage named
  local name="$1"; shift
  echo "=== S: $name ==="
  if "$@"; then
    echo "--- $name : PASS"
  else
    echo "--- $name : FAIL"
    FAILED_STAGE="$name"
    exit 1
  fi
}

# S1 chassis: M0 install.sh (idempotent re-run)
stage "S1 chassis (owning gate: TP-M0)" \
  bash "$REPO_ROOT/deploy-v2/m0/install.sh" --no-gate

# S2 adapter: M1 compose up + consumer-healthy check
stage "S2 adapter (owning gate: M1 §4 / TP-M1)" \
  ssh "$VM_XB" "cd /opt/ea/deploy-v2/m1 && $(xb_engine) compose up -d topic-bridge"
stage "S2 adapter consumer healthy" \
  ssh "$VM_XB" "$(xb_engine) logs m1-topic-bridge-1 2>&1 | grep -qiE 'consumer|consuming'"

# S3 lifecycle: M2 compose up + deploy gate (pinned images present) + worker registered
stage "S3 lifecycle deploy gate (pinned image exists — no-pull rule)" \
  ssh "$VM_XB" "$(xb_engine) image inspect ea/executor-stub:1.0.0 >/dev/null"
stage "S3 lifecycle compose up" \
  ssh "$VM_XB" "cd /opt/ea/deploy-v2/m2 && $(xb_engine) compose up -d"
stage "S3 lifecycle healthy" \
  ssh "$VM_XB" "$(xb_engine) exec m2-lifecycle-1 curl -sf http://127.0.0.1:8090/health"
stage "S3 worker registered (polling temporal)" \
  ssh "$VM_XB" "$(xb_engine) logs m2-worker-1 2>&1 | grep -qiE 'WorkflowType TaskWorkflow|worker started|registered'"

# S4 executors: M3 images load-verified on vm-xb; token issuance dry-run
stage "S4 executor images present on vm-xb" \
  ssh "$VM_XB" "$(xb_engine) image inspect ea/hermes-ephemeral:1.0.0 >/dev/null && $(xb_engine) image inspect ea/claude-coder:1.0.0 >/dev/null"
stage "S4 token issuance dry-run (issue + verify + revoke)" \
  ssh "$VM_XB" "set -a; . /opt/ea/secrets/m3.env; set +a; bash /opt/ea/deploy-v2/m3/issue-token.sh --dry-run"

# S5 memory: M4 hindsight compose up on vm-hindsight + /healthz check
# (the llm-wiki is a git repo cloned by the executor at boot — no service here)
stage "S5 hindsight compose up (vm-hindsight)" \
  ssh "$VM_HINDSIGHT" "cd /opt/ea/deploy-v2/m4/hindsight && docker compose up -d"
stage "S5 hindsight /healthz" \
  ssh "$VM_HINDSIGHT" "curl -sf http://127.0.0.1:8081/healthz"

# S6 front-house: M5 compose up on vm-xa + gateway /healthz
stage "S6 front-house compose up (vm-xa)" \
  ssh "$VM_XA" "cd /opt/ea/deploy-v2/m5 && docker compose up -d"
stage "S6 gateway /healthz" \
  ssh "$VM_XA" "curl -sf http://127.0.0.1:8083/healthz"

# S7 smoke: one M2-level task with the stub executor (proves S2–S3 before real agents)
stage "S7 smoke task (stub executor through the full flow)" \
  bash "$REPO_ROOT/deploy-v2/m2/tests/run-task.sh" "{\"task_id\":\"s7-smoke-$(date +%s)\",\"executor\":\"stub\",\"agent_ref\":\"ephemeral-org/eph-backend-engineer\",\"agent_repo_url\":\"https://github.com/arvisdev/agent-roster\",\"repo_folder\":\"ephemeral-org/eph-backend-engineer\",\"repo_target\":\"repos/ea-demo-repo\",\"task_prompt\":\"S7 smoke: confirm the flow\",\"max_turns\":3,\"behavioral_spec\":\"S7 end-to-end smoke\",\"requester\":\"m5-s7\",\"ttl_s\":300}"

echo "=== e2e-deploy: all stages S1–S7 PASS ==="
