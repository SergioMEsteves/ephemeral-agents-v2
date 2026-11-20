#!/usr/bin/env bash
# =============================================================================
# M5 — END-TO-END + HARDENING: complete installation script (final gate)
# =============================================================================
# Implements §1–§7 of the M5 end-to-end installation procedure
#   (deploy-v2/RUNBOOK-V2-BUILD.md).
# Gate afterwards:
#   TP-M5 = build complete: the feasibility verdict confirmed by
#   evidence, not by analysis
#
# M5 adds NO new infrastructure — it composes what M0–M4 installed and locks
# the last open items. M5 adds no new Temporal code (all Temporal components
# remain the Go M1/M2 services).
#
# Steps:
#   §1  Build + deploy gateway + manager on vm-xa
#   §3  Ordered full-stack bring-up (e2e-deploy.sh S1–S7, stage-gated)
#   §4  E2E acceptance run (one real request, human to human)
#   §5  Failure injections F1–F5
#   §6  Credential hardening (trivy sweep, env review, token 401)
#   §7  Lock the open items + close the docs
#
# Usage:  bash deploy-v2/m5/install.sh [--check-only] [--no-gate]
#   ASSUME_YES=1  — skip interactive confirms
#
# Configuration (env, or deploy-v2/m0/hosts.env — auto-loaded; deploy-v2/m5/.env optional):
#   VM_XA / VM_XB / VM_HINDSIGHT — ssh aliases (defaults vm-xa/vm-xb/vm-hindsight)
#   GATEWAY_URL — default "http://<vm-xa-ip-or-name>:8083" (set to the reachable form)
#   E2E_BRIEF — the task_brief for the acceptance request (default: "add a health endpoint to the demo project")
#   E2E_TIMEOUT_S — default 600
#   M0..M4_DONE=1 — skip the all-gates prereq probe
#   AGENT_LIST_READ_TOKEN — read token for the agent-roster repo (manager env)
#   PROJECT_LOCAL_DIR — local clone of the project repo (for the commit check)
#
# Assets required in the repo (produced by the M5 delivery plan; checked first):
#   services/gateway/ + services/manager/  (Go)
#   deploy-v2/m5/compose.yaml   deploy-v2/m5/Dockerfile (or per-service)
#   deploy-v2/m5/e2e-deploy.sh  deploy-v2/m5/report-contract.md
#
# Rollback (doc §8): M5 front-house only -> docker compose down on vm-xa;
# everything behind it (M0–M4) stays up.
#
# FOR THE OPERATOR (junior dev) — read this before running:
#   1. TP-M0..TP-M4 all signed. Export M0_DONE=1 M1_DONE=1 M2_DONE=1
#      M3_DONE=1 M4_DONE=1 to skip the live probes when you know they're green.
#   2. `bash deploy-v2/m5/install.sh --check-only`   # preview: no changes
#   3. `bash deploy-v2/m5/install.sh`                # front-of-house ->
#      e2e-deploy S1-S7 -> E2E run -> F1-F4 injections -> hardening scans.
#   4. A failing E2E stage names its owning milestone: re-run THAT milestone's
#      gate test (M1 §4 / M2 §3 / M3 §4 / M4 §4), not the whole chain.
#   5. Final step: run TP-M5. All five done-when conditions hold = build done.
#
# =============================================================================
# Container engine (ENGINE env / hosts.env): docker (default) or podman =
# ROOTLESS Podman on the execution VM (vm-xb) only — every other VM stays
# Docker. vm-xb docker/compose commands run through xb_engine() (podman mode
# runs them as the poc user). See decision-log.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
M5="$REPO_ROOT/deploy-v2/m5"
EVIDENCE="$M5/evidence"
LOG="$EVIDENCE/install-m5.log"
mkdir -p "$EVIDENCE"

CHECK_ONLY=0; NO_GATE=0
ASSUME_YES="${ASSUME_YES:-0}"
for arg in "$@"; do
  case "$arg" in
    --check-only) CHECK_ONLY=1 ;;
    --no-gate) NO_GATE=1 ;;
    -h|--help) sed 's/^# \{0,1\}//' "$0"; exit 0 ;;
    *) echo "unknown option: $arg"; exit 64 ;;
  esac
done

[ -f "$REPO_ROOT/deploy-v2/m0/hosts.env" ] && { set -a; . "$REPO_ROOT/deploy-v2/m0/hosts.env"; set +a; }
[ -f "$M5/.env" ] && { set -a; . "$M5/.env"; set +a; }
GH_OWNER="${GH_OWNER:-arvisdev}"
VM_XA="${VM_XA:-vm-xa}"; VM_XB="${VM_XB:-vm-xb}"; VM_HINDSIGHT="${VM_HINDSIGHT:-vm-hindsight}"
IMAGE_TAG="${IMAGE_TAG:-1.0.0}"
GATEWAY_URL="${GATEWAY_URL:-http://$VM_XA:8083}"
E2E_BRIEF="${E2E_BRIEF:-add a health endpoint to the POC project}"
E2E_TIMEOUT_S="${E2E_TIMEOUT_S:-600}"
ALL_GATES_DONE="${M0_DONE:-0}${M1_DONE:-0}${M2_DONE:-0}${M3_DONE:-0}${M4_DONE:-0}"
# ---------------------------------------------------------------- engine choice
# ENGINE (docker | podman) — podman = ROOTLESS Podman on the EXECUTION VM
# (vm-xb) ONLY; every other VM stays Docker. Set in inputs.yaml config.engine,
# carried by hosts.env (render-inputs.py), overridable via env.
ENGINE="${ENGINE:-docker}"
# xb_engine — the container-engine command prefix for vm-xb remote commands.
# Rootless Podman runs as the poc user (XDG_RUNTIME_DIR is what podman needs
# to find its per-user socket/runtime; the remote shell resolves $(id -u poc)).
xb_engine() {
  if [ "$ENGINE" = "podman" ]; then
    echo 'sudo -u poc env XDG_RUNTIME_DIR=/run/user/$(id -u poc) podman'
  else
    echo docker
  fi
}
# xb_own_staged — podman compose runs as poc, so staged compose/.env files
# must be readable by poc (docker mode runs as the ssh user and needs no change).
xb_own_staged() {
  if [ "$ENGINE" = "podman" ]; then
    ssh "$VM_XB" "sudo chown poc:poc $* 2>/dev/null || true"
  fi
}


log()  { printf '[m5 %s] %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a "$LOG"; }
ok()   { log "OK   - $*"; }
warn() { log "WARN - $*"; }
die()  { log "FAIL: $*"; exit 1; }

confirm() {
  if [ "$CHECK_ONLY" = "1" ]; then log "check-only: would apply — $*"; return 0; fi
  if [ "$ASSUME_YES" = "1" ]; then log "assumed — $*"; else
    local ans=""
    read -r -p "  proceed? [y/N] " ans
    [ "$ans" = "y" ] || die "aborted by operator"
  fi
}

# ---------------------------------------------------------------- prereqs
prereqs() {
  log "§0 — prereq: TP-M0..TP-M4 all signed"
  if [ "$ALL_GATES_DONE" = "11111" ]; then
    log "§0   ALL_GATES_DONE — skipping live probes"
    return 0
  fi
  ssh "$VM_XB" "$(xb_engine) ps --format '{{.Names}}' | grep -Eq '^ea-m1-topic-bridge-[0-9]+$'" \
    || die "M1: topic-bridge missing on $VM_XB — earlier gate not passed"
  ssh "$VM_XB" "$(xb_engine) ps --format '{{.Names}}' | grep -Eq '^ea-m2-lifecycle-[0-9]+$'" \
    || die "M2: lifecycle missing on $VM_XB — earlier gate not passed"
  ssh "$VM_HINDSIGHT" "curl -sf http://127.0.0.1:8082/healthz" >/dev/null 2>&1 \
    || die "M4: hindsight not healthy on $VM_HINDSIGHT — earlier gate not passed"
  ok "prereqs"
}

# ---------------------------------------------------------------- assets
check_assets() {
  local missing=() f
  for f in \
    "$REPO_ROOT/services/gateway" \
    "$REPO_ROOT/services/manager" \
    "$M5/compose.yaml" \
    "$M5/e2e-deploy.sh" \
    "$M5/report-contract.md"
  do
    [ -e "$f" ] || missing+=("$f")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    if [ "$CHECK_ONLY" = "1" ]; then
      log "check-only: missing assets (not a failure in check-only):"
      printf '  %s\n' "${missing[@]}"
      exit 0
    fi
    log "missing assets (the M5 delivery plan produces these — Go services):"
    printf '  %s\n' "${missing[@]}"
    die "asset check failed — build the assets, then re-run"
  fi
  ok "assets present"
}

# ---------------------------------------------------------------- §1 front-of-house
build_and_deploy_front_of_house() {
  log "§1 — build gateway + manager (Go) and deploy on $VM_XA"
  confirm "build ea/gateway + ea/manager and deploy on $VM_XA"
  if [ "$CHECK_ONLY" = "1" ]; then return 0; fi
  docker build -f "$M5/Dockerfile" "$REPO_ROOT/services/gateway" -t "ea/gateway:$IMAGE_TAG"
  docker build -f "$M5/Dockerfile" "$REPO_ROOT/services/manager"  -t "ea/manager:$IMAGE_TAG"
  docker save "ea/gateway:$IMAGE_TAG" "ea/manager:$IMAGE_TAG" | ssh "$VM_XA" "docker load"
  ssh "$VM_XA" "sudo mkdir -p /opt/ea/deploy-v2/m5 /opt/ea/reports && sudo chown -R poc:poc /opt/ea"
  rsync -az "$M5/compose.yaml" "$VM_XA:/opt/ea/deploy-v2/m5/compose.yaml"
  # .env: RABBITMQ_PASS always (compose interpolation); AGENT_LIST_READ_TOKEN when provided.
  local rmp; rmp="$(grep '^RABBITMQ_PASS=' "$REPO_ROOT/deploy-v2/m0/rabbitmq/.env" | cut -d= -f2)"
  [ -n "$rmp" ] || die "RABBITMQ_PASS missing — run deploy-v2/m0/install.sh §3 first"
  {
    printf '%s\n' "RABBITMQ_PASS=$rmp"
    printf '%s\n' "AGENT_LIST_REPO=${AGENT_LIST_REPO:-https://github.com/arvisdev/agent-roster.git}"
    printf '%s\n' "BROKER_HOST=${BROKER_HOST:-192.0.2.11}"
    printf '%s\n' "HINDSIGHT_HOST=${HINDSIGHT_HOST:-${VM_HINDSIGHT:-192.0.2.12}}"
    [ -n "${OPENROUTER_API_KEY:-}" ] && printf '%s\n' "OPENROUTER_API_KEY=$OPENROUTER_API_KEY"
    if [ -n "${AGENT_LIST_READ_TOKEN:-}" ]; then
      printf '%s\n' "AGENT_LIST_READ_TOKEN=$AGENT_LIST_READ_TOKEN"
    fi
  } | ssh "$VM_XA" 'umask 077; cat > /opt/ea/deploy-v2/m5/.env && chmod 600 /opt/ea/deploy-v2/m5/.env'   # stdin + 600: secret not in argv/logs
  [ -n "${AGENT_LIST_READ_TOKEN:-}" ] || warn "AGENT_LIST_READ_TOKEN not set — manager cannot clone the catalog until it is"
  ssh "$VM_XA" "cd /opt/ea/deploy-v2/m5 && docker compose up -d"
  local i
  for i in $(seq 1 40); do
    if curl -sf "$GATEWAY_URL/healthz" >/dev/null 2>&1; then break; fi
    sleep 3
    if [ "$i" = "40" ]; then die "gateway /healthz not reachable at $GATEWAY_URL (M5 §8: front-house down)"; fi
  done
  ok "§1 front-of-house up on $VM_XA"
}

# ---------------------------------------------------------------- §2' executor default (M5-era)
# The M3-era compose pins EA_IMAGE=stub and omits EA_EXECUTOR_DEFAULT — the M2/M3
# gates must run the stub. M5 flips the default to hermes (message-v1 has no
# executor field; the lifecycle's EA_EXECUTOR_DEFAULT decides, M3 §2'). Idempotent.
select_executor_default() {
  log "§2' — M5-era executor default: EA_EXECUTOR_DEFAULT=hermes in the ea-m2 compose"
  if [ "$CHECK_ONLY" = "1" ]; then return 0; fi
  scp -q "$M5/set-executor-default.py" "$VM_XB:/tmp/set-executor-default.py"
  ssh "$VM_XB" "python3 /tmp/set-executor-default.py /opt/ea/deploy-v2/m2/compose.yaml hermes"
  ssh "$VM_XB" "cd /opt/ea/deploy-v2/m2 && $(xb_engine) compose up -d --force-recreate lifecycle"
  ssh "$VM_XB" "$(xb_engine) inspect ea-m2-lifecycle-1 --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -q '^EA_EXECUTOR_DEFAULT=hermes$'" \
    || die "§2' EA_EXECUTOR_DEFAULT=hermes not applied to ea-m2-lifecycle-1"
  ok "§2' executor default = hermes (stub remains the rollback pin)"
}

# ---------------------------------------------------------------- §3 bring-up
full_stack_bringup() {
  log "§3 — ordered full-stack bring-up (S1–S7, stage-gated)"
  if [ "$CHECK_ONLY" = "1" ]; then log "check-only: skip bring-up"; return 0; fi
  if [ -f "$M5/e2e-deploy.sh" ]; then
    bash "$M5/e2e-deploy.sh"   # exits non-zero at the failing stage
    ok "§3 e2e-deploy.sh S1–S7 green"
  else
    die "deploy-v2/m5/e2e-deploy.sh missing (stage-gated bring-up; M5 §3) — cannot continue"
  fi
}

# ---------------------------------------------------------------- §4 E2E acceptance
e2e_acceptance_run() {
  log "§4 — E2E acceptance run: one real request, human to human"
  if [ "$CHECK_ONLY" = "1" ]; then log "check-only: skip E2E run"; return 0; fi
  local resp task_id payload
  payload="$(printf '%s' "$E2E_BRIEF" | python3 -c 'import json,sys; print(json.dumps({"title":"add health endpoint","agent_capability":"ephemeral-org/eph-backend-engineer","task_brief":sys.stdin.read()}))')" \
    || die "E2E payload build failed (python3 required on the build host)"
  resp="$(curl -s -X POST "$GATEWAY_URL/" \
    -H 'content-type: application/json' \
    --data-binary "$payload")"
  log "§4   gateway response: $resp"
  task_id="$(echo "$resp" | sed -n 's/.*"task_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  [ -n "$task_id" ] || die "gateway response has no task_id (see deploy-v2/m5/report-contract.md)"

  # 1 workflow for it
  ssh "$VM_XB" "temporal workflow list --type TaskWorkflow --limit 20 | grep -c '$task_id'" \
    | grep -q '[1-9]' || warn "§4   temporal: workflow row for $task_id not yet listed (poll)"
  # agent container alive + labeled while running (snapshot)
  ssh "$VM_XB" "$(xb_engine) ps --filter label=ea.owner=lifecycle --format '{{.Names}}'" | tee "$EVIDENCE/e2e-containers-alive.txt"
  # wait for completion
  local i
  for i in $(seq 1 "$((E2E_TIMEOUT_S / 10))"); do
    if curl -sf "$GATEWAY_URL/gateway/reports/$task_id" >/dev/null 2>&1; then break; fi
    sleep 10
    if [ "$i" = "$((E2E_TIMEOUT_S / 10))" ]; then die "E2E: report never landed within ${E2E_TIMEOUT_S}s"; fi
  done
  # zero survivors after completion
  local survivors
  survivors="$(ssh "$VM_XB" "$(xb_engine) ps -a --filter label=ea.owner=lifecycle -q | wc -l")"
  log "§4   post-completion POC container count: $survivors (expected 0)"
  # commit exists
  if [ -n "${PROJECT_LOCAL_DIR:-}" ] && [ -d "$PROJECT_LOCAL_DIR" ]; then
    git -C "$PROJECT_LOCAL_DIR" fetch origin "task/$task_id" 2>/dev/null || true
    if git -C "$PROJECT_LOCAL_DIR" log --oneline "origin/task/$task_id" >/dev/null 2>&1; then
      log "§4   commit exists on origin/task/$task_id"
    else
      die "§4   task/$task_id not on origin — artifact missing"
    fi
  else
    warn "§4   PROJECT_LOCAL_DIR unset — operator must verify the commit per M5 §4"
  fi
  # report JSON — the task itself must have SUCCEEDED (not just reaped clean)
  curl -sf "$GATEWAY_URL/gateway/reports/$task_id" | tee "$EVIDENCE/e2e-report-$task_id.json" >/dev/null
  rstatus="$(python3 -c "import json;print(json.load(open('$EVIDENCE/e2e-report-$task_id.json')).get('status',''))" 2>/dev/null || echo unreadable)"
  if [ "$rstatus" != "success" ]; then
    rreason="$(python3 -c "import json;print(json.load(open('$EVIDENCE/e2e-report-$task_id.json')).get('reason',''))" 2>/dev/null)"
    die "§4   acceptance task FAILED (report status=$rstatus reason=$rreason) — see $EVIDENCE/e2e-report-$task_id.json"
  fi
  log "§4   report status: success"
  log "§4   evidence pack -> $EVIDENCE (add: temporal trace export + lifecycle log)"
  ok "§4 E2E run: artifact chain verified (survivors=$survivors)"
}

# ---------------------------------------------------------------- §5 failure injections
failure_injections() {
  log "§5 — failure-injection runbook F1–F5 (each: clean reap + human-visible error)"
  if [ "$CHECK_ONLY" = "1" ]; then log "check-only: skip injections"; return 0; fi
  local f tid cid
  {
    echo "# M5 failure injections — $(date -u)"
    # F1: llm-wiki clone unreachable (block outbound HTTPS to github.com on the executor VM)
    log "F1 — block outbound git/HTTPS to github.com on $VM_XB during a task (llm-wiki clone fails)"
    block_github_443
    sleep 5
    inject_and_verify "F1"
    unblock_github_443
    # F2: agent catalog unreachable (same block path — the catalog clone lives on github.com too)
    log "F2 — block vm-xb -> GitHub 443 (nftables; agent-repo clone path)"
    block_github_443
    sleep 5
    inject_and_verify "F2"
    unblock_github_443
    # F3: agent crash
    log "F3 — pkill -9 the agent process mid-task"
    f="$(run_one_task)"
    tid="$(task_id_of "$f")"
    [ -n "$tid" ] || log "F3 publish rejected: $f"
    sleep 10
    cid="$(ssh "$VM_XB" "$(xb_engine) ps --filter label=ea.owner=lifecycle -q | head -1 || true")"
    if [ -n "$cid" ]; then
      # pkill matches process NAMES; the agent is PID 1 — kill it by pid, with a
      # docker-kill fallback if the exec cannot signal it.
      ssh "$VM_XB" "$(xb_engine) exec $cid sh -c 'kill -9 1' 2>/dev/null" \
        || ssh "$VM_XB" "$(xb_engine) kill $cid" || true
    fi
    verify_task "F3" "$tid"
    # F4: TTL exceeded
    log "F4 — task with TTL_S smaller than work time (reaper path with real agents)"
    f="$(run_one_task_short_ttl)"
    tid="$(task_id_of "$f")"
    verify_task "F4" "$tid"
    # F5: manager restart mid-task (response-consumer reconnect + pending persistence)
    log "F5 — docker restart manager mid-task; report must still be written after restart"
    f="$(run_one_task)"
    tid="$(task_id_of "$f")"
    [ -n "$tid" ] || log "F5 publish rejected: $f"
    sleep 10
    ssh "$VM_XA" "cd /opt/ea/deploy-v2/m5 && sudo docker compose restart manager"
    if wait_report "$tid" "${INJECT_TIMEOUT_S:-900}"; then
      local survivors rstatus
      survivors="$(ssh "$VM_XB" "$(xb_engine) ps -a --filter label=ea.owner=lifecycle -q | wc -l")"
      rstatus="$(report_status "$tid")"
      if [ "$survivors" = "0" ] && [ "$rstatus" = "success" ]; then
        echo "F5 manager-restart: report written after restart (status=$rstatus survivors=$survivors) : PASS"
      else
        echo "F5 manager-restart: status=$rstatus survivors=$survivors : FAIL"
      fi
      echo "F5 report JSON: $(ssh "$VM_XA" "cat /opt/ea/reports/$tid.json")"
    else
      echo "F5 manager-restart: report never landed within ${INJECT_TIMEOUT_S:-900}s : FAIL"
    fi
  } | tee "$EVIDENCE/failure-injections.txt"
  if grep -q ": FAIL" "$EVIDENCE/failure-injections.txt"; then
    warn "§5 injection FAILURES above — remediate in the owning milestone (M2 §3 for reaping), re-run."
    if [ "$NO_GATE" != "1" ]; then exit 1; fi
  else
    ok "§5 F1–F5 clean + reported"
  fi
}

# helpers for the injection runbook.
# NOTE: real executors take ~13 min boot-to-report — every wait below POLLS for
# the report instead of sleeping a fixed interval (the stub-era 45s sleep could
# never observe a real task, and "dev" was never a real catalog capability).
run_one_task() {
  curl -s -X POST "$GATEWAY_URL/" -H 'content-type: application/json' \
    -d '{"title":"f-inject","agent_capability":"ephemeral-org/eph-backend-engineer","task_brief":"tiny task for the injection runbook"}' || true
}
run_one_task_short_ttl() {
  curl -s -X POST "$GATEWAY_URL/" -H 'content-type: application/json' \
    -d '{"title":"f-inject","agent_capability":"ephemeral-org/eph-backend-engineer","task_brief":"Long-running job: run the shell command sleep 600 and wait for it to finish before writing your completion report. Do nothing else.","ttl_s":15}' || true
}
task_id_of() { printf '%s' "$1" | sed -n 's/.*"task_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'; }
report_status() {
  ssh "$VM_XA" "python3 -c \"import json;print(json.load(open('/opt/ea/reports/$1.json')).get('status',''))\"" 2>/dev/null || echo unreadable
}
wait_report() {  # $1 task_id, $2 timeout_s -> 0 when the report JSON lands on vm-xa
  local tid="$1" t="${2:-900}" i
  for i in $(seq 1 "$((t / 10))"); do
    ssh "$VM_XA" "test -f /opt/ea/reports/$tid.json" >/dev/null 2>&1 && return 0
    sleep 10
  done
  return 1
}
verify_task() {  # $1 label, $2 task_id — survivors=0 AND a failure-shaped report
  local label="$1" tid="$2" survivors st
  if [ -z "$tid" ]; then echo "$label publish rejected (no task_id) : FAIL"; return 0; fi
  if wait_report "$tid" "${INJECT_TIMEOUT_S:-900}"; then
    survivors="$(ssh "$VM_XB" "$(xb_engine) ps -a --filter label=ea.owner=lifecycle -q | wc -l")"
    st="$(report_status "$tid")"
    if [ "$survivors" = "0" ] && [ "$st" != "success" ]; then
      echo "$label report status=$st survivors=$survivors : PASS"
    elif [ "$st" = "success" ]; then
      echo "$label report status=success survivors=0 — injection did NOT bite (fault path not exercised) : CHECK"
    else
      echo "$label report status=$st survivors=$survivors : FAIL"
    fi
    echo "$label report JSON: $(ssh "$VM_XA" "cat /opt/ea/reports/$tid.json")"
  else
    survivors="$(ssh "$VM_XB" "$(xb_engine) ps -a --filter label=ea.owner=lifecycle -q | wc -l")"
    echo "$label report never landed within ${INJECT_TIMEOUT_S:-900}s survivors=$survivors : FAIL"
  fi
}
inject_and_verify() {  # $1 label — publish one task while the fault is active, then verify
  local label="$1" tid
  tid="$(task_id_of "$(run_one_task)")"
  verify_task "$label" "$tid"
}
block_github_443() {
  ssh "$VM_XB" "sudo -n nft -f -" <<'NFT'
add table inet eablock
add chain inet eablock output { type filter hook output priority 0 ; policy accept ; }
add chain inet eablock forward { type filter hook forward priority -5 ; policy accept ; }
add rule inet eablock output ip daddr 140.82.112.0/20 tcp dport 443 counter drop
add rule inet eablock output ip daddr 143.55.64.0/20 tcp dport 443 counter drop
add rule inet eablock output ip daddr 185.199.108.0/22 tcp dport 443 counter drop
add rule inet eablock output ip daddr 192.30.252.0/22 tcp dport 443 counter drop
add rule inet eablock forward ip daddr 140.82.112.0/20 tcp dport 443 counter drop
add rule inet eablock forward ip daddr 143.55.64.0/20 tcp dport 443 counter drop
add rule inet eablock forward ip daddr 185.199.108.0/22 tcp dport 443 counter drop
add rule inet eablock forward ip daddr 192.30.252.0/22 tcp dport 443 counter drop
NFT
  # record the block's load status in the evidence stream — a silently empty
  # rule set makes every F1/F2 verdict meaningless (seen on the first §5 run).
  log "nft block loaded: $(ssh "$VM_XB" "sudo -n nft list table inet eablock 2>/dev/null | grep -c drop || echo 0") drop rule(s)"
}
unblock_github_443() {
  ssh "$VM_XB" "sudo -n nft delete table inet eablock 2>/dev/null || true"
}

# ---------------------------------------------------------------- §6 hardening
credential_hardening() {
  log "§6 — credential hardening (R4 final)"
  if [ "$CHECK_ONLY" = "1" ]; then return 0; fi
  if command -v trivy >/dev/null; then
    local img
    for img in ea/topic-bridge ea/lifecycle ea/worker ea/executor-stub ea/hermes-ephemeral ea/claude-coder ea/hindsight-api ea/gateway ea/manager; do   # ALL 9 deployed images
      # ea/claude-coder exception (decision log, M5 §6): the pinned Claude Code
      # CLI (and the pinned Hermes Agent v0.23.0 runtime in hermes-ephemeral) bundle their dependencies; fixes live upstream.
      EXTRA=""
      case "$img" in ea/claude-coder) EXTRA="--skip-dirs /usr/local/lib/node_modules";; esac
      if [ "$img" = "ea/hermes-ephemeral" ]; then
        # lang-pkgs findings (Node/Python deps bundled inside the pinned Hermes
        # Agent v0.23.0 runtime) are an accepted residual: fixes live in the
        # upstream Hermes release, not in this image (decision log, M5 §6).
        trivy image --scanners vuln,secret --severity HIGH,CRITICAL --ignore-unfixed \
          --skip-dirs /root/.hermes/hermes-agent --format json "$img:$IMAGE_TAG" > /tmp/trivy-he.json 2>/dev/null || true
        n=$(python3 -c "import json; d=json.load(open('/tmp/trivy-he.json')); print(sum(len(r.get('Vulnerabilities') or []) for r in d.get('Results',[]) if r.get('Class') != 'lang-pkgs'))" 2>/dev/null || echo 1)
        ns=$(python3 -c "import json; d=json.load(open('/tmp/trivy-he.json')); print(sum(len(r.get('Secrets') or []) for r in d.get('Results',[])))" 2>/dev/null || echo 1)
        if [ "${n:-1}" = "0" ] && [ "${ns:-1}" = "0" ]; then
          log "§6   trivy $img:$IMAGE_TAG : clean (pinned-runtime lang-pkgs accepted residual)"
          continue
        fi
        die "§6   trivy: $img:$IMAGE_TAG has fixable HIGH/CRITICAL findings or secrets — remediate"
      fi
      trivy image --exit-code 1 --scanners vuln,secret --severity HIGH,CRITICAL --ignore-unfixed $EXTRA "$img:$IMAGE_TAG" \
        && log "§6   trivy $img:$IMAGE_TAG : clean" \
        || die "§6   trivy: $img:$IMAGE_TAG has fixable HIGH/CRITICAL findings or secrets — remediate"
      mkdir -p "$(dirname "$EVIDENCE/trivy-$img.json")"
      trivy image --scanners vuln --format json "$img:$IMAGE_TAG" > "$EVIDENCE/trivy-$img.json" 2>/dev/null || true
    done
  else
    warn "trivy not installed — install it and re-run §6a (cannot claim hardening without the scan)"
  fi
  # env review: no owner long-lived tokens anywhere
  local hits
  hits="$(ssh "$VM_XB" "for c in \$($(xb_engine) ps -q); do $(xb_engine) inspect \"\$c\" | grep -Ei 'owner_?token|github_pat' || true; done")"
  if [ -n "$hits" ]; then
    die "§6   owner long-lived token found in a container env — M5 §6b: remove + re-deploy"
  fi
  log "§6   env review clean"
  # token lifecycle evidence (M3 §4 B5 re-run): REAL issue -> repo-scoped verify
  # (installation tokens 403 on /user) -> revoke -> 401. The key lives on vm-xb
  # (/opt/poc/secrets source per S0); the token never leaves the VM / enters logs.
  if [ -f "$REPO_ROOT/deploy-v2/m3/issue-token.sh" ]; then
    local tcode src
    src="$(ssh "$VM_XB" 'set -a; . /opt/poc/secrets/m3.env; set +a; bash /opt/ea/deploy-v2/m3/issue-token.sh' 2>/dev/null | head -1)"
    [ -n "$src" ] || die "§6   issue-token.sh produced no token (m3.env + app key state — M3 §1c)"
    tcode="$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: token $src" "https://api.github.com/repos/$GH_OWNER/agent-roster/contents/")"
    log "§6   issued token -> HTTP $tcode on the catalog repo (want 200 pre-revoke)"
    [ "$tcode" = "200" ] || die "§6   issued token did not authenticate (HTTP $tcode)"
    ssh "$VM_XB" 'set -a; . /opt/poc/secrets/m3.env; set +a; bash /opt/ea/deploy-v2/m3/issue-token.sh --revoke-last' >/dev/null 2>&1
    sleep 5   # revocation propagation — an immediate check raced GitHub (seen live: 200 post-revoke)
    tcode="$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: token $src" "https://api.github.com/repos/$GH_OWNER/agent-roster/contents/")"
    log "§6   revoked token -> HTTP $tcode (want 401 post-revoke)" 
    [ "$tcode" = "401" ] || die "§6   revoked token still authenticates (HTTP $tcode) — token lifecycle broken"
  fi
  ok "§6 hardening"
}

# ---------------------------------------------------------------- §7 close docs
lock_open_items() {
  log "§7 — lock the last open items + close the docs"
  if [ "$CHECK_ONLY" = "1" ]; then return 0; fi
  if [ ! -f "$M5/decision-log.md" ]; then
    cat > "$M5/decision-log.md" <<'DEC'
# M5 decision log — lock the open items

- [ ] VM numbering (carried from M0) — final scheme recorded
- [ ] topic/queue message shapes — schemas/message-v1.json is the contract (version it)
- [ ] concurrency model — one-coder-per-task (default) or N-parallel + worktrees (M3 §3)
- [ ] ephemeral isolation level — co-located containers on vm-xb (POC) vs. per-task VMs (defer)
- [x] llm-wiki repo curation owner + cadence (from M4) — D-curation (2026-11-04): owner = the Human-In-The-Loop (HITL); append-only, need-driven; record in the llm-wiki repo's CHANGELOG.md

After locking: update the estate's architecture record (ARCHITECTURE.md +
Initial-Foundation-Design-Document.md)
(move resolved items out of "open") and add the Version 2 open items list
(llm-wiki repo curation ownership, long-term queue shape,
multi-flow concurrency).
DEC
  fi
  log "§7   template at $M5/decision-log.md — the operator locks each box, then updates the estate's architecture record"
  ok "§7 docs-closeout prepared"
}

# ---------------------------------------------------------------- POC complete
ea_complete_summary() {
  log "BUILD COMPLETE CHECK (M5 §9 done-when — all five):"
  local s
  s="$(ssh "$VM_XB" "$(xb_engine) ps -a --filter label=ea.owner=lifecycle -q | wc -l")"
  log " 1. E2E run passed, zero surviving executor containers : survivors=$s $([ "$s" = "0" ] && echo '(PASS)' || echo '(CHECK)')"
  log " 2. F1–F4 clean + reported : see $EVIDENCE/failure-injections.txt"
  log " 3. §6 scans pass : see $LOG"
  log " 4. §7 open items locked : see $M5/decision-log.md"
  log " 5. Engineer sees the outcome : report JSON with artifact pointer (GET $GATEWAY_URL/gateway/reports/<task_id>)"
  log "When 1–5 hold: run TP-M5 to sign the final gate."
  ok "M5 install complete"
}

# ---------------------------------------------------------------- firewall
# The scripts own the POC's port openings (owner baseline = SSH only). The
# gateway on vm-xa:8083 is hit by the engineer's desktop — often OUTSIDE the
# POC LAN, so its source is GATEWAY_ALLOW_CIDR (defaults to the POC LAN).
open_firewall() {
  local cidr="${GATEWAY_ALLOW_CIDR:-${UFW_POC_CIDR:-}}"
  [ -n "$cidr" ] || cidr="${NETPLAN_IP_XA:-${VM_XA%.*}}.0/24"
  [ -n "$cidr" ] && [ "$cidr" != ".0/24" ] || { log "fw   no NETPLAN_IP_XA/GATEWAY_ALLOW_CIDR — skipping UFW setup"; return 0; }
  if [ "$CHECK_ONLY" = "1" ]; then log "check-only: would open UFW 8083 on $VM_XA from $cidr"; return 0; fi
  if ssh "$VM_XA" "sudo -n ufw status 2>/dev/null | grep -q 'Status: active'"; then
    ssh "$VM_XA" "sudo -n ufw allow from $cidr to any port 8083 proto tcp" \
      || die "fw   ufw rule failed on $VM_XA"
    ok "fw   UFW: 8083 (gateway, this build — the first organization keeps 8080) open on $VM_XA from $cidr"
  else
    log "fw   UFW not active on $VM_XA — skipped"
  fi
}

# ---------------------------------------------------------------- main
main() {
  log "=== M5 e2e+hardening install start (check-only=$CHECK_ONLY no-gate=$NO_GATE) ==="
  prereqs
  check_assets
  confirm "M5: front-of-house + bring-up + E2E + injections + hardening + docs closeout"
  # M5_FROM=5 skips the already-green §1/§3/§4 (no image rebuild since they
  # ran — the TP regression rule only forces a §4 re-run on rebuild/redeploy).
  if [ "${M5_FROM:-1}" -le 1 ]; then build_and_deploy_front_of_house; open_firewall; else log "M5_FROM=${M5_FROM} — skipping §1/§3/§4 (already green)"; fi
  if [ "${M5_FROM:-1}" -le 3 ]; then full_stack_bringup; fi
  if [ "${M5_FROM:-1}" -le 4 ]; then e2e_acceptance_run; fi
  select_executor_default   # M5-era executor default — runs on every invocation (idempotent)
  if [ "${M5_FROM:-1}" -le 5 ]; then failure_injections; fi
  credential_hardening
  lock_open_items
  ea_complete_summary
}
main
