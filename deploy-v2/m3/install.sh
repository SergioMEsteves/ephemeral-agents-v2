#!/usr/bin/env bash
# =============================================================================
# M3 — EXECUTOR SPIKES (Hermes Ephemeral + Claude Code): complete install
# =============================================================================
# Implements §1–§5 of:
#   version 1/installation-deployment/M3-Executors-Installation-and-Deployment.md
# Gate afterwards:
#   version 1/test procedures/M3-Executors-Test-Procedure.md  (TP-M3 must PASS
#   before the M4 installation may begin)
#
# Steps:
#   §1  GitHub-side checks (catalog repo, project repo, App key, token dry-run)
#   §2  Build + load ea/hermes-ephemeral:1.0.0 + ea/claude-coder:1.0.0
#       (executors run their own runtimes — tooling, NOT Temporal code, so
#       outside the Go mandate; no M1/M2 Go code is touched here)
#   §2' Select the executor images in the M2 config (EA_IMAGE switch)
#   §3  Concurrency model decision (recorded, default: one-coder-per-task)
#   §4  Verification B1..B5 (+B6 if N-parallel) -> deploy-v2/m3/evidence/
#   §5  Secret hygiene checks (env dumps, image history, trivy)
#
# Usage:  bash deploy-v2/m3/install.sh [--check-only] [--no-gate]
#   ASSUME_YES=1  — skip interactive confirms
#
# Configuration (env, or deploy-v2/m0/hosts.env — auto-loaded; deploy-v2/m3/.env optional):
#   VM_XB  — ssh alias for vm-xb (default "vm-xb")
#   M2_DONE=1   — skip prereq probes
#   CATALOG_REPO / PROJECT_REPO — git URLs or owner/account-scoped names for gh checks
#   APP_KEY_PATH — default /opt/ea/secrets/app-key.pem on $VM_XB
#   N_PARALLEL=1 — choose the N-parallel concurrency model (default: one-coder)
#   PROJECT_LOCAL_DIR — local clone of the project repo on the build host (for B4 commit check)
#
# Assets required in the repo (produced by the M3 delivery plan; checked first):
#   deploy-v2/m3/hermes-ephemeral/Dockerfile + entrypoint.sh
#   deploy-v2/m3/claude-coder/Dockerfile     + entrypoint.sh
#   deploy-v2/m3/issue-token.sh   (JWT-signed; curl + openssl, ~20 lines; runs on vm-xb)
#   deploy-v2/m3/tests/boot-time.sh   deploy-v2/m2/tests/run-task.sh
#
# Rollback (doc §6): rebuild + re-load; M2 keeps its stub pin until new tags
# pass, so a bad M3 image never takes down the lifecycle.
#
# FOR THE OPERATOR (junior dev) — read this before running:
#   1. M2 gate signed. The owner does the GitHub-side setup once (App + key +
#      install, doc §1c); the script verifies it and runs the token dry-run.
#   2. `bash deploy-v2/m3/install.sh --check-only`   # preview: no changes
#   3. `bash deploy-v2/m3/install.sh`                # build both executor images
#      -> select them in M2 -> B1..B5 gate tests -> secret-hygiene scans.
#   4. This is the POC's point of last cheap exit: a failure here is still a
#      two-week fix. Evidence -> deploy-v2/m3/evidence/, then run TP-M3.
#
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
M3="$REPO_ROOT/deploy-v2/m3"
EVIDENCE="$M3/evidence"
LOG="$EVIDENCE/install-m3.log"
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
[ -f "$M3/.env" ] && { set -a; . "$M3/.env"; set +a; }
VM_XB="${VM_XB:-vm-xb}"
IMAGE_TAG="${IMAGE_TAG:-1.0.0}"
APP_KEY_PATH="${APP_KEY_PATH:-/opt/ea/secrets/app-key.pem}"
N_PARALLEL="${N_PARALLEL:-0}"

log()  { printf '[m3 %s] %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a "$LOG"; }
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
  log "§0 — prereq checks (M2 gate)"
  [ "${M2_DONE:-0}" = "1" ] || {
    if ! ssh "$VM_XB" "docker ps --format '{{.Names}}' | grep -Eq '^ea-m2-(lifecycle|worker)$'"; then
      die "lifecycle/worker not running on $VM_XB — run M2 install first"
    fi
  }
  command -v gh >/dev/null || warn "gh CLI not found — GitHub-side checks (§1) will be printed, not executed"
  ok "prereqs"
}

# ---------------------------------------------------------------- assets
check_assets() {
  local missing=() f
  for f in \
    "$M3/hermes-ephemeral/Dockerfile" \
    "$M3/hermes-ephemeral/entrypoint.sh" \
    "$M3/claude-coder/Dockerfile" \
    "$M3/claude-coder/entrypoint.sh" \
    "$M3/issue-token.sh" \
    "$M3/tests/boot-time.sh"
  do
    [ -e "$f" ] || missing+=("$f")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    if [ "$CHECK_ONLY" = "1" ]; then
      log "check-only: missing assets (not a failure in check-only):"
      printf '  %s\n' "${missing[@]}"
      exit 0
    fi
    log "missing assets (the M3 delivery plan produces these):"
    printf '  %s\n' "${missing[@]}"
    die "asset check failed — build the assets, then re-run"
  fi
  ok "assets present"
}

# ---------------------------------------------------------------- §1 github-side
github_side() {
  log "§1 — GitHub-side checks (owner's workstation; do-once setup verified)"
  if [ "$CHECK_ONLY" = "1" ]; then return 0; fi
  if command -v gh >/dev/null; then
    for repo in "${CATALOG_REPO:-agent-roster}" "${PROJECT_REPO:-ea-demo-repo}"; do
      if gh repo view "$repo" --json name >/dev/null 2>&1; then
        log "§1   repo $repo : present"
      else
        log "§1   repo $repo : MISSING (M3 §1a/1b — create it on the owner's account)"
      fi
    done
  fi
  # App private key on vm-xb (presence + perms only — never print it)
  if ssh "$VM_XB" "test -r $APP_KEY_PATH" ; then
    local perms; perms="$(ssh "$VM_XB" "stat -c '%a' $APP_KEY_PATH")"
    log "§1   app key present at $APP_KEY_PATH (perms $perms — must be 600)"
    [ "$perms" = "600" ] || warn "app key perms are $perms, expected 600 (M3 §1c)"
  else
    die "App private key missing on $VM_XB ($APP_KEY_PATH) — M3 §1c: create the GitHub App, save the PEM key, chmod 600. Never in git or any image."
  fi
  # token dry-run: issue + verify + revoke
  log "§1   token issuance dry-run (issue -> verify -> revoke)"
  if [ -x "$M3/issue-token.sh" ] || [ -f "$M3/issue-token.sh" ]; then
    local token
    token="$(bash "$M3/issue-token.sh" --dry-run)"
    [ -n "$token" ] || die "issue-token.sh produced no token (check key + installation_id, M3 §1c)"
    local code; code="$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: token $token" https://api.github.com/user)"
    [ "$code" = "200" ] || die "issued token did not authenticate (HTTP $code)"
    bash "$M3/issue-token.sh" --revoke-last || true
    code="$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: token $token" https://api.github.com/user)"
    log "§1   token revocation check: HTTP $code (expected 401/403)"
    [ "$code" != "200" ] || warn "token still valid after revoke — GitHub App installation tokens expire at 1 h max (M3 §7)"
  else
    warn "issue-token.sh not executable / missing script body — dry-run skipped (owner must complete M3 §1c)"
  fi
  ok "§1 github-side"
}

# ---------------------------------------------------------------- §2 build
build_and_load() {
  log "§2 — build both executor images and load onto $VM_XB"
  confirm "build ea/hermes-ephemeral + ea/claude-coder (outside the Go mandate: these run their own tooling runtimes)"
  if [ "$CHECK_ONLY" = "1" ]; then return 0; fi
  docker build -f "$M3/hermes-ephemeral/Dockerfile" "$M3/hermes-ephemeral" -t "ea/hermes-ephemeral:$IMAGE_TAG"
  docker build -f "$M3/claude-coder/Dockerfile" "$M3/claude-coder" -t "ea/claude-coder:$IMAGE_TAG"
  docker save "ea/hermes-ephemeral:$IMAGE_TAG" "ea/claude-coder:$IMAGE_TAG" | ssh "$VM_XB" "docker load"
  ok "§2 executor images built + loaded"
}

stage_m3_secrets() {
  log "§2\" — stage M3 secrets on $VM_XB (app key + m3.env + token script)"
  if [ "$CHECK_ONLY" = "1" ]; then return 0; fi
  # S0 policy: preserve V1 credentials — copy the live V1 app key + m3.env values
  # into the V2 secret paths (never mint, never print). m3.env carries the per-run
  # env keys m3FromEnv() expects (GITHUB_APP_ID/INSTALLATION_ID, MODEL_DEFAULT,
  # ANTHROPIC_API_KEY base, etc.). The token script runs on the VM; repo copy is
  # the source of truth.
  ssh "$VM_XB" "sudo mkdir -p /opt/ea/secrets /opt/ea/deploy/m3 && sudo chown -R \"\$(id -un):\$(id -gn)\" /opt/ea/secrets /opt/ea/deploy/m3"
  ssh "$VM_XB" "sudo test -r /opt/poc/secrets/app-key.pem && sudo cp /opt/poc/secrets/app-key.pem /opt/ea/secrets/app-key.pem || die 'V1 app key missing at /opt/poc/secrets/app-key.pem'" \
    || die "app-key copy from V1 failed"
  ssh "$VM_XB" "sudo test -r /opt/poc/secrets/m3.env && sudo cp /opt/poc/secrets/m3.env /opt/ea/secrets/m3.env || true"
  ssh "$VM_XB" "chmod 600 /opt/ea/secrets/app-key.pem /opt/ea/secrets/m3.env && chmod 700 /opt/ea/deploy/m3"
  rsync -az "$M3/issue-token.sh" "$VM_XB:/opt/ea/deploy/m3/issue-token.sh" \
    && ssh "$VM_XB" "chmod 700 /opt/ea/deploy/m3/issue-token.sh" \
    || die "issue-token.sh rsync failed"
  # verify the staged m3.env carries the keys m3FromEnv() needs (names only)
  local missing_keys
  missing_keys="$(ssh "$VM_XB" "for k in GITHUB_APP_ID INSTALLATION_ID MODEL_DEFAULT; do grep -q \"^\$k=\" /opt/ea/secrets/m3.env || echo \$k; done" || true)"
  [ -z "$missing_keys" ] || die "m3.env missing keys (staged from V1 — verify /opt/poc/secrets/m3.env): $missing_keys"
  ok "§2\" M3 secrets staged (key + m3.env + token script; values never printed)"
}

select_images_in_m2() {
  log "§2' — select executor images in the M2 config (EA_IMAGE switch; writes the M3-era compose)"
  if [ "$CHECK_ONLY" = "1" ]; then return 0; fi
  # The M2-era compose (stub-only) must be replaced by the M3-era state: the
  # executor switch (EA_IMAGE_HERMES/CODER pins, tag pins — images are loaded
  # locally by §2, no registry pull at spawn) + m3.env env_file + M3 §1c mounts.
  cat > "$REPO_ROOT/deploy-v2/m2/compose.m3-era.yaml" <<YAML
# M3-era m2 compose — written by deploy-v2/m3/install.sh §2' (config switch,
# not a code change). Executor images are TAG pins loaded locally (M3 §2);
# the M5 install rewrites this with digest pins + EA_EXECUTOR_DEFAULT.
name: ea-m2
services:
  lifecycle:
    image: "ea/lifecycle:1.0.0"
    environment:
      DOCKER_HOST: "unix:///var/run/docker.sock"
      LISTEN: "0.0.0.0:8090"
      REAPER_INTERVAL: "30s"
      EA_TTL_DEFAULT: "900s"
      EA_IMAGE: "ea/executor-stub:1.0.0"
      EA_IMAGE_HERMES: "ea/hermes-ephemeral:1.0.0"
      EA_IMAGE_CODER: "ea/claude-coder:1.0.0"
      EA_DOCKER_DEBUG: "true"                 # M3 debug: log exact docker run args
    env_file:
      - /opt/ea/secrets/m3.env                # M3 §2 per-run secrets (never in git/images)
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "/opt/ea/deploy/m3:/opt/ea/deploy/m3:ro"   # M3 §1c: token-issuance script
      - "/opt/ea/secrets:/opt/ea/secrets:ro"       # M3 §1c: app-key.pem (read-only)
      - "/var/ea/tasks:/var/ea/tasks"
    restart: unless-stopped
    # deploy gate (deploy-v2/m2/install.sh): entrypoint refuses to serve until
    # the pinned image exists locally (no-pull rule).
  worker:
    image: "ea/worker:1.0.0"
    entrypoint: ["/usr/local/bin/worker"]
    environment:
      TEMPORAL_ADDR: "\${EA_TEMPORAL_ADDR:-temporal:7233}"
      LIFECYCLE_API: "http://lifecycle:8090"
      EA_DOCKER_DEBUG: "true"
      RABBITMQ_URL: "amqp://ea:\${RABBITMQ_PASS:?set RABBITMQ_PASS in .env}@rabbitmq:5672/"
    depends_on: [lifecycle]
    restart: unless-stopped
networks:
  default:
    external: true
    name: ea-net
YAML
  rsync -az "$REPO_ROOT/deploy-v2/m2/compose.m3-era.yaml" "$VM_XB:/opt/ea/deploy-v2/m2/compose.yaml" \
    || die "M3-era compose rsync failed"
  # ensure the m2 .env (RABBITMQ_PASS) still exists — compose interpolation needs it
  ssh "$VM_XB" "test -s /opt/ea/deploy-v2/m2/.env" || die "m2 .env missing — re-run deploy-v2/m2/install.sh §2"
  ssh "$VM_XB" "cd /opt/ea/deploy-v2/m2 && docker compose up -d --force-recreate lifecycle worker" \
    || die "M2 recreate with the M3-era compose failed"
  ssh "$VM_XB" "docker image inspect ea/hermes-ephemeral:$IMAGE_TAG >/dev/null && docker image inspect ea/claude-coder:$IMAGE_TAG >/dev/null" \
    || die "M2 no-pull gate: executor images missing on $VM_XB after reload"
  ok "§2' M2 config switched to the selected images (M3-era compose live)"
}

# ---------------------------------------------------------------- §3 concurrency
concurrency_decision() {
  log "§3 — concurrency model (R3)"
  if [ "$N_PARALLEL" = "1" ]; then
    log "§3   model: N-parallel coders via git worktrees (M2 config change: fan out N spawns)"
  else
    log "§3   model: DEFAULT one-coder-per-task (one container, one task/<id> branch, no shared checkout)"
  fi
  if [ "$CHECK_ONLY" != "1" ] && [ ! -f "$M3/concurrency-decision.md" ]; then
    {
      echo "# M3 concurrency model decision — $(date +%F)"
      echo "- Model: $([ "$N_PARALLEL" = "1" ] && echo "N-parallel + git worktrees" || echo "one-coder-per-task (default)")"
      echo "- Rationale: record here (R3: shared-checkout write conflicts vs. parallel throughput)"
      echo "- Impact: M2 config only — not a new image (M3 §3)"
    } > "$M3/concurrency-decision.md"
  fi
  ok "§3 concurrency model recorded"
}

# ---------------------------------------------------------------- §4 gate tests
gate_tests() {
  log "§4 — verification B1..B5$( [ "$N_PARALLEL" = "1" ] && echo B6 ) (the M3 gate tests) -> $EVIDENCE/"
  local out="$EVIDENCE/m3-tests.txt"
  if [ "$CHECK_ONLY" = "1" ]; then log "check-only: skip gate tests"; return 0; fi
  local task_id
  {
    echo "# M3 gate tests — $(date -u)"
    # B1 boot-time x3
    bash "$M3/tests/boot-time.sh" hermes 3 2>&1 | tee "$EVIDENCE/boot-time-table.txt" \
      && echo "B1 boot-time: table recorded (record p50, set the acceptance bound, re-run to pass)"
    # B2 persona correctness
    if [ -f "$EVIDENCE/self-report.json" ] || [ -f "$M3/tests/self-report.json" ]; then
      echo "B2 persona: self-report present (verify role/skills/spec vs agents/dev-agent/ — record in $EVIDENCE)"
    else
      echo "B2 persona: RUN the self-report assertion manually (M3 §4 B2) and record"
    fi
    # B3 failure paths
    echo "B3 failure: operator runs (a) unreachable AGENT_REPO_URL and (b) malformed persona -> both exit 2 + reap (record in $EVIDENCE)"
    # B4 coder real work
    if [ -n "${PROJECT_LOCAL_DIR:-}" ] && [ -d "$PROJECT_LOCAL_DIR" ]; then
      task_id="m3b-$(date +%H%M%S)"
      if bash "$REPO_ROOT/deploy-v2/m2/tests/run-task.sh" "{\"task_id\":\"$task_id\",\"executor\":\"coder\",\"agent_ref\":\"ephemeral-org/eph-backend-engineer\",\"agent_repo_url\":\"https://github.com/$CATALOG_REPO\",\"repo_folder\":\"ephemeral-org/eph-backend-engineer\",\"task_prompt\":\"add a /healthz handler to the ea-demo Go service: respond 200 'ok' on /healthz\",\"behavioral_spec\":\"WP-C01\",\"repo_target\":\"github.com/$PROJECT_REPO\",\"requester\":\"m3-b4\",\"ttl_s\":600}" >/dev/null 2>&1; then
        git -C "$PROJECT_LOCAL_DIR" fetch origin "task/$task_id" 2>/dev/null || true
        if git -C "$PROJECT_LOCAL_DIR" log --oneline "origin/task/$task_id" >/dev/null 2>&1; then
          echo "B4 coder: commit exists on origin/task/$task_id : PASS"
        else
          echo "B4 coder: task/$task_id not found on origin : FAIL (check M3 §7: contents:write on the project repo)"
        fi
      else
        echo "B4 coder: M2 run-task failed : FAIL"
      fi
    else
      echo "B4 coder: set PROJECT_LOCAL_DIR to a local clone of the project repo (manual per M3 §4 B4)"
    fi
    # B5 token lifecycle
    echo "B5 token: post-reap token must be 401 (re-run the §1 dry-run revoke check; record output)"
    # B6 only if N-parallel
    if [ "$N_PARALLEL" = "1" ]; then
      echo "B6 n-parallel: 2 concurrent coders -> 2 branches, both push, no lost work (record)"
    fi
  } | tee "$out"
  if grep -q ": FAIL" "$out"; then
    warn "M3 gate tests: FAILURES above — remediate per M3 §7, re-run from the failed test."
    if [ "$NO_GATE" != "1" ]; then exit 1; fi
  else
    ok "M3 gate tests recorded (complete the manual B2/B3/B5 lines in $out before signing TP-M3)"
    log "Next: run TP-M3 — version 1/test procedures/M3-Executors-Test-Procedure.md (file evidence in $EVIDENCE)."
  fi
}

# ---------------------------------------------------------------- §5 secret hygiene
secret_hygiene() {
  log "§5 — secret hygiene checks (R4, run before claiming done)"
  if [ "$CHECK_ONLY" = "1" ]; then return 0; fi
  local f1="$EVIDENCE/env-hermes.txt" f2="$EVIDENCE/env-coder.txt"
  docker run --rm "ea/hermes-ephemeral:$IMAGE_TAG" env > "$f1"
  docker run --rm "ea/claude-coder:$IMAGE_TAG" env > "$f2"
  if grep -Ei 'token|key|secret' "$f1" "$f2"; then
    die "secrets baked into an image env — M3 §5: secrets are injected at spawn, never baked (rebuild without them)"
  fi
  log "§5   image env dumps clean (secrets are injected at spawn)"
  for img in "ea/hermes-ephemeral:$IMAGE_TAG" "ea/claude-coder:$IMAGE_TAG"; do
    if docker history --no-trunc "$img" | grep -Eiq 'secret|token'; then
      die "a RUN layer wrote secrets into $img — M3 §5: rebuild without them"
    fi
  done
  log "§5   docker history: no secret-writing layers"
  if command -v trivy >/dev/null; then
    trivy image --exit-code 1 "ea/hermes-ephemeral:$IMAGE_TAG" "ea/claude-coder:$IMAGE_TAG" \
      && log "§5   trivy: secrets vuln class = 0" \
      || die "trivy found issues — remediate before claiming done"
  else
    warn "trivy not installed on the build host — install it (R4) and re-run this check"
  fi
  ok "§5 secret hygiene"
}

# ---------------------------------------------------------------- main
main() {
  log "=== M3 executor install start (check-only=$CHECK_ONLY no-gate=$NO_GATE) ==="
  prereqs
  check_assets
  confirm "M3: github-side + build + select + gate-test the executor spikes"
  github_side
  build_and_load
  stage_m3_secrets
  select_images_in_m2
  concurrency_decision
  gate_tests
  secret_hygiene
  log "=== M3 install complete ==="
}
main
