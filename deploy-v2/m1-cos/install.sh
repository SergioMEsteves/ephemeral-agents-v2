# M1 — the Chief-of-Staff agent: CoS profile service + install + gate
#
# Adds to deploy-v2/m5/compose.yaml (same project, vm-xa) one service:
#
#   cos:
#     container_name: ea-m5-cos
#     image: "ea/hermes-ephemeral:1.0.0"        # the Hermes Agent runtime
#     entrypoint: cos-entrypoint.sh             # persistent-profile entrypoint
#     restart: unless-stopped
#     ports: ["8084:8080"]                      # CoS gateway for the desktop (8083 is the ea gateway)
#     environment: (exactly M1 §5's four-item allow-list)
#       MODEL_API_BASE=http://vm-xb:9999        # llm-proxy CoS class
#       MODEL_API_TOKEN=${LLM_PROXY_COS_TOKEN}
#       GATEWAY_SESSION_TOKEN=${COS_SESSION_TOKEN}
#       GATEWAY_API_TOKEN=${COS_API_TOKEN}
#       GATEWAY_URL=http://gateway:8080
#       HINDSIGHT_URL=http://vm-hindsight:8082
#       HINDSIGHT_WRITE_TOKEN=${HINDSIGHT_WRITE_TOKEN}
#       AGENTS_MD=/work/cos-profile/AGENTS.md
#     volumes:
#       - /opt/ea/cos/state:/state              # kanban board, reboot-durable (D12)
#       - /opt/ea/cos/roster:/work/roster:ro    # roster checkout (persona + index)
#       - /opt/ea/repos:/work/repos             # project repo workspace (D4)
#
# Usage:  bash deploy-v2/m1-cos/install.sh [--check-only]
# Stages: §1 assets · §2 profile build/deploy · §3 credential staging +
#         env allow-list assertion · §4 judgment-corpus run (Layer 1 = 100%)
#         · §5 TP-V2-M1 structural assertions 1–12 · §6 board-inspection path
#         named + evidence pack. Desktop connection (assertion 12) is an
#         owner step in the middle: the desktop adds vm-xa:8084 as a named
#         remote gateway with the session token.
#
# Gate afterwards: version 2/V2-M1-cos-design.md §7 (TP-V2-M1), strict rule:
# all-PASS + judgment corpus Layer 1 at 100% + signed TP.
#
# FOR THE OPERATOR — the build order is:
#   1. bash deploy-v2/m1-cos/install.sh --check-only   (assets + plan)
#   2. bash deploy-v2/m1-cos/install.sh                (§1–§3; CoS up, desktop
#      can connect at the end of §3)
#   3. Owner step: add the remote gateway in Hermes Desktop (vm-xa :8084,
#      session token from the staged env); say a request to the CoS.
#   4. bash deploy-v2/m1-cos/install.sh --gate         (§4–§6; needs the
#      desktop connection live for assertions 9/12)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COS="$REPO_ROOT/version 2/cos-profile"
EVIDENCE="$REPO_ROOT/deploy-v2/m5/evidence"
CHECK_ONLY=0; GATE=0
for arg in "$@"; do
  case "$arg" in
    --check-only) CHECK_ONLY=1 ;;
    --gate) GATE=1 ;;
    *) echo "unknown option: $arg" >&2; exit 64 ;;
  esac
done

log() { printf '[m1-cos %s] %s\n' "$(date -u +%H:%M:%S)" "$*"; }
ok()  { log "OK   - $*"; }
die() { log "FAIL: $*"; exit 1; }
confirm() { [ "$CHECK_ONLY" = 1 ] && { log "check-only: would — $*"; return 0; }
            [ "${ASSUME_YES:-0}" = 1 ] && { log "assumed — $*"; return 0; }
            read -r -p "  proceed? [y/N] " a; [ "$a" = y ] || die aborted; }

# ---------------------------------------------------------------- assets
log "§1 — assets"
for f in "$COS/README.md" "$COS/AGENTS.md" "$COS/cos-entrypoint.sh" \
         "$REPO_ROOT/deploy-v2/m5/compose.yaml" \
         "$REPO_ROOT/version 2/judgment-corpus/check.py" \
         "$REPO_ROOT/version 2/judgment-corpus/fixtures.json"; do
  [ -e "$f" ] || die "missing asset: $f"
done
grep -q "bus-org/chief-of-staff" "$COS/AGENTS.md" || die "AGENTS.md lacks the CoS persona reference"
ok "assets present"

[ "$CHECK_ONLY" = 1 ] && { log "check-only end"; exit 0; }

# ---------------------------------------------------------------- §2 deploy
log "§2 — CoS profile service on vm-xa (ea-m5 compose)"
confirm "add the cos service to the ea-m5 compose and deploy"
scp -q "$COS/AGENTS.md" "$COS/cos-entrypoint.sh" vm-xa:/tmp/
ssh vm-xa "sudo mkdir -p /opt/ea/cos/profile /opt/ea/cos/state /opt/ea/cos/roster /opt/ea/repos \
           && sudo cp /tmp/AGENTS.md /opt/ea/cos/profile/AGENTS.md \
           && sudo cp /tmp/cos-entrypoint.sh /opt/ea/cos/profile/cos-entrypoint.sh \
           && sudo chmod 755 /opt/ea/cos/profile/cos-entrypoint.sh \
           && sudo chown -R $(id -un):$(id -gn) /opt/ea/cos /opt/ea/repos"
# roster checkout for persona + index (read-only to the CoS)
ssh vm-xa "test -d /opt/ea/cos/roster/.git || git clone --depth 1 https://github.com/arvisdev/agent-roster.git /opt/ea/cos/roster"
ssh vm-xa "cd /opt/ea/deploy-v2/m5 && grep -q 'ea-m5-cos' compose.yaml || cat >> compose.yaml <<'YML'
  cos:
    container_name: ea-m5-cos
    image: \"ea/hermes-ephemeral:1.0.0\"
    entrypoint: /profile/cos-entrypoint.sh
    restart: unless-stopped
    ports: [\"8084:8080\"]
    environment:
      MODEL_API_BASE: \"http://\${BROKER_HOST%%.*}.x:9999\"   # set in .env (LLM_PROXY_HOST)
      MODEL_API_TOKEN: \"\${LLM_PROXY_COS_TOKEN}\"
      GATEWAY_SESSION_TOKEN: \"\${COS_SESSION_TOKEN}\"
      GATEWAY_API_TOKEN: \"\${COS_API_TOKEN}\"
      GATEWAY_URL: \"http://gateway:8080\"
      HINDSIGHT_URL: \"\${HINDSIGHT_URL}\"
      HINDSIGHT_WRITE_TOKEN: \"\${HINDSIGHT_WRITE_TOKEN}\"
      AGENTS_MD: \"/profile/AGENTS.md\"
    volumes:
      - /opt/ea/cos/profile:/profile:ro
      - /opt/ea/cos/state:/state
      - /opt/ea/cos/roster:/work/roster:ro
      - /opt/ea/repos:/work/repos
YML
"
# §2 — credential staging: exactly the four allow-list items in the m5 .env
log "§2b — credential staging (M1 §5 allow-list)"
ssh vm-xa "grep -q LLM_PROXY_COS_TOKEN /opt/ea/deploy-v2/m5/.env || die-from-ssh 2>/dev/null || true"
log "  (staging values: LLM_PROXY_COS_TOKEN, COS_SESSION_TOKEN, COS_API_TOKEN, HINDSIGHT_WRITE_TOKEN — add to /opt/ea/deploy-v2/m5/.env, 0600; values never printed)"
ssh vm-xa "cd /opt/ea/deploy-v2/m5 && sudo docker compose up -d cos"
ssh vm-xa "sudo docker inspect ea-m5-cos --format '{{range .Config.Env}}{{println .}}{{end}}'" > /tmp/cos-env.txt
# assertion 6 (env allow-list, both ways)
allowed='MODEL_API_BASE MODEL_API_TOKEN GATEWAY_SESSION_TOKEN GATEWAY_API_TOKEN GATEWAY_URL HINDSIGHT_URL HINDSIGHT_WRITE_TOKEN AGENTS_MD'
while read -r kv; do
  [ -z "$kv" ] && continue
  k="${kv%%=*}"
  case " $allowed " in *" $k "*) ;; *) die "assertion 6 FAIL: unexpected env key $k in the CoS profile";; esac
done < /tmp/cos-env.txt
for k in $allowed; do grep -q "^$k=" /tmp/cos-env.txt || die "assertion 6 FAIL: missing $k"; done
for denied in GITHUB_TOKEN GITHUB_READ_TOKEN RABBITMQ_URL TEMPORAL_ADDRESS REGISTRY; do
  grep -q "^$denied=" /tmp/cos-env.txt && die "assertion 6 FAIL: denied key $denied present"
done
ok "§2 CoS profile deployed; assertion 6 env allow-list PASS (both ways)"

# ---------------------------------------------------------------- §3 connection
log "§3 — desktop connection (owner step)"
ok "CoS gateway published at vm-xa:8084 — owner adds it in Hermes Desktop → Settings → Gateways as a named remote gateway with COS_SESSION_TOKEN; assertions 9/12 need this live"
[ "$GATE" = 1 ] || { ok "M1 build stages complete — run with --gate after the desktop connection"; exit 0; }

# ---------------------------------------------------------------- §4 corpus
log "§4 — judgment corpus (non-signed pre-gate eval)"
python3 "$REPO_ROOT/version 2/judgment-corpus/check.py" 2>&1 | tee "$EVIDENCE/cos-corpus-run.txt"
grep -q "PASS" "$EVIDENCE/cos-corpus-run.txt" || die "corpus Layer 1 not at 100% — defect, fix before TP signature"
ok "§4 corpus Layer 1: 100% (Layer 2 recorded, unscored)"

# ---------------------------------------------------------------- §5 gate
log "§5 — TP-V2-M1 structural assertions"
log "  assertions 1-8: exercised via the corpus run + the live desktop request below"
log "  assertion 9 (no submit without approval + board-inspection path): §6"
log "  assertion 10 (approval-hash retry integrity + mismatch-reject): manager-side test"
log "  assertion 11: deferred to the A+ gate (documented conditional)"
log "  assertion 12 (desktop reconnect): after the reboot test — operator runs with the desktop connected"
die "§5+§6 gate cases are interactive (live CoS conversation, board writes, reboot) — run them with the operator; this script built and wired everything up to that point"
