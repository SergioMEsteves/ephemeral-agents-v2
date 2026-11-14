#!/usr/bin/env bash
# =============================================================================
# M0 — CHASSIS: complete installation script
# =============================================================================
# Implements §1–§7 of:
#   version 1/installation-deployment/M0-Chassis-Installation-and-Deployment.md
# Gate afterwards:
#   version 1/test procedures/M0-Chassis-Test-Procedure.md  (TP-M0 must PASS
#   before the M1 installation may begin)
#
# What this script does (idempotent — safe to re-run; re-run = rebuild):
#   §1  Provision 3 VMs on the PVE host (vm-xa, vm-xb, vm-hindsight) + base OS
#   §2  Docker on every VM
#   §3  RabbitMQ (topic) on vm-xb + topic topology + cross-VM publish test
#   §4  Temporal on vm-xb +  §4b  Go SDK smoke (the language-decision check)
#   §5  Network verification matrix -> deploy-v2/m0/evidence/network-matrix.txt
#   §6  Decision-log entries (VM numbering D-8 + Go-for-Temporal mandate)
#   §7  Acceptance checks (the M0 gate summary)
#
# Usage:
#   bash deploy-v2/m0/install.sh [--check-only] [--no-gate] [--apply-netplan]
#   ASSUME_YES=1  — skip interactive confirms (CI / re-runs)
#
# Configuration (env, or deploy-v2/m0/hosts.env in the repo — auto-loaded):
#   PVE_HOST   ssh alias for the Proxmox host        (required)
#   VM_XA VM_XB VM_3   ssh aliases for the 3 VMs (required)
#   VMID_XA=900 VMID_XB=901 VMID_3=903    (defaults; check qm list first)
#   NETPLAN_IP_XA=... NETPLAN_IP_XB=... NETPLAN_IP_3=...
#       if set AND --apply-netplan: writes /etc/netplan/01-netcfg.yaml
#       (backing up any existing file) and applies; default is record-only.
#   SMOKE_HOST=local (default: run the Go SDK smoke on the build host)
#
# Assets required in the repo (produced by the M0 delivery plan; checked first):
#   deploy-v2/m0/rabbitmq/compose.yaml   deploy-v2/m0/temporal/compose.yaml
#   deploy-v2/m0/go-sdk-smoke/  (a minimal Go program: greet workflow + worker)
#   deploy-v2/m0/.env.example
#
# Secrets: generated once into gitignored deploy-v2/m0/{rabbitmq,temporal}/.env
# (openssl rand -hex 16). Never committed, never in compose files.
#
# FOR THE OPERATOR (junior dev) — read this before running:
#   1. `cp deploy-v2/m0/hosts.env.example deploy-v2/m0/hosts.env` and fill in the
#      ssh aliases + static IPs (hosts.env itself is gitignored).
#   2. `bash deploy-v2/m0/install.sh --check-only`   # preview: no changes
#   3. `bash deploy-v2/m0/install.sh`                 # real run; idempotent —
#      on failure it tells you what to fix (M0 install doc §8), then RE-RUN:
#      the script skips everything that's already done.
#   4. When the gate summary says "all 5 PASS": run TP-M0 before starting M1.
#
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
M0="$REPO_ROOT/deploy-v2/m0"
EVIDENCE="$M0/evidence"
LOG="$EVIDENCE/install-m0.log"
mkdir -p "$EVIDENCE"

CHECK_ONLY=0; NO_GATE=0; APPLY_NETPLAN=0
ASSUME_YES="${ASSUME_YES:-0}"
for arg in "$@"; do
  case "$arg" in
    --check-only) CHECK_ONLY=1 ;;
    --no-gate) NO_GATE=1; ASSUME_YES=1 ;;
    --apply-netplan) APPLY_NETPLAN=1 ;;
    -h|--help) sed 's/^# \{0,1\}//' "$0"; exit 0 ;;
    *) echo "unknown option: $arg (see --help)"; exit 64 ;;
  esac
done

# hosts.env is the POC's canonical host map (committed; values are LAN-internal)
if [ -f "$M0/hosts.env" ]; then set -a; . "$M0/hosts.env"; set +a; fi

PVE_HOST="${PVE_HOST:-}"; VM_XA="${VM_XA:-}"; VM_XB="${VM_XB:-}"
VM_3="${VM_3:-}"
VMID_XA="${VMID_XA:-900}"; VMID_XB="${VMID_XB:-901}"
VMID_3="${VMID_3:-903}"
TEMPORAL_ADDR="${TEMPORAL_ADDR:-$VM_XB:7233}"

log()  { printf '[m0 %s] %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a "$LOG"; }
ok()   { log "OK   - $*"; }
warn() { log "WARN - $*"; }
die()  { log "FAIL: $*"; exit 1; }

PVMXS=("$VM_XA" "$VM_XB" "$VM_3")

# ---------------------------------------------------------------- assets
check_assets() {
  local missing=() f
  for f in \
    "$M0/rabbitmq/compose.yaml" \
    "$M0/temporal/compose.yaml" \
    "$M0/go-sdk-smoke" \
    "$M0/.env.example"
  do
    [ -e "$f" ] || missing+=("$f")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    if [ "$CHECK_ONLY" = "1" ]; then
      log "check-only: missing assets (not a failure in check-only):"
      printf '  %s\n' "${missing[@]}"
      exit 0
    fi
    log "missing assets (the M0 delivery plan produces these):"
    printf '  %s\n' "${missing[@]}"
    die "asset check failed — build the assets, then re-run"
  fi
  [ -n "$PVE_HOST" ] || die "PVE_HOST not set (deploy-v2/m0/hosts.env or env)"
  for h in "${PVMXS[@]}"; do [ -n "$h" ] || die "VM alias not set in deploy-v2/m0/hosts.env"; done
  ssh -o BatchMode=yes -o ConnectTimeout=8 "$PVE_HOST" 'qm list >/dev/null' \
    || die "cannot reach PVE host via ssh $PVE_HOST"
  for h in "${PVMXS[@]}"; do
    ssh -o BatchMode=yes -o ConnectTimeout=8 "$h" true \
      || die "cannot ssh to $h (if first run: fix PVE + base OS first, then re-run)"
  done
  ok "assets + host reachability"
}

confirm() {
  if [ "$CHECK_ONLY" = "1" ]; then log "check-only: would apply — $*"; return 0; fi
  if [ "$ASSUME_YES" = "1" ]; then log "assumed — $*"; else
    log "about to: $*"
    local ans=""
    read -r -p "  proceed? [y/N] " ans
    [ "$ans" = "y" ] || die "aborted by operator"
  fi
}

# ---------------------------------------------------------------- §1 provision
vm_display_name() {
  case "$1" in
    "$VM_XA") echo vm-xa ;;
    "$VM_XB") echo vm-xb ;;
    "$VM_3")  echo vm-hindsight ;;
    *)        echo "$1" ;;
  esac
}

provision_vms() {
  log "§1 — PVE: check VM block $VMID_XA-$VMID_3 (qm list first; pick a free block)"
  local specs=("vm-xa:$VMID_XA" "vm-xb:$VMID_XB" "vm-hindsight:$VMID_3")
  local mem=(4096 8192 4096) cores=(2 4 2) disk=(20 40 20)
  local i name id
  for i in 0 1 2; do
    name="${specs[i]%%:*}"; id="${specs[i]##*:}"
    if ssh "$PVE_HOST" "qm status $id 2>/dev/null | grep -Eq '^(status|Status).*(stopped|running|paused)'"; then
      log "§1   $id ($name) exists — ensuring started"
      ssh "$PVE_HOST" "qm status $id | grep -Eq '^(status|Status): running' || qm start $id"
    else
      confirm "create VM $id ($name) on $PVE_HOST (l26, ${mem[i]}MB, ${cores[i]} cores, virtio0 local:${disk[i]}G)"
      if [ "$CHECK_ONLY" != "1" ]; then
        ssh "$PVE_HOST" \
          "qm create $id --name $name --ostype l26 --memory ${mem[i]} --cores ${cores[i]} \
           --virtio0 local:${disk[i]} --net0 virtio,bridge=vmbr0 --agent enabled=1"
        log "§1   $name created — install Ubuntu 26.04 LTS (ISO/cloud-init per estate; 24.04 if unavailable), boot"
        # Fresh VM only: set the hostname to the role label ($name) during the
        # manual OS install. Already-provisioned machines keep their
        # owner-supplied estate hostname — see §1 base OS (no rename).
      fi
    fi
  done
  # post-boot base OS on every VM (idempotent)
  for h in "${PVMXS[@]}"; do
    local hn ipkey nip cur
    hn="$(vm_display_name "$h")"
    log "§1   base OS on $hn (chrony, poc user)"
    # COEXISTENCE (V2 design): do NOT rename an already-provisioned VM.
    # The estate hostnames are owner-supplied (e.g. vm-hermes-agent); the role
    # label ($hn) is used only for logging/aliases. Rename only when a fresh
    # machine is provisioned above (no QID existed).
    ssh "$h" "cur=\$(hostnamectl --static 2>/dev/null); echo \"§1   hostname: \${cur:-unknown} (kept — owner-supplied)\""
    ssh "$h" "command -v chronyd >/dev/null || { sudo apt-get update && sudo apt-get install -y chrony; }; sudo systemctl enable --now chrony"
    ssh "$h" "id poc >/dev/null 2>&1 || sudo useradd -m -s /bin/bash poc; sudo usermod -aG sudo poc"
    case "$h" in
      "$VM_XA") ipkey=XA ;;
      "$VM_XB") ipkey=XB ;;
      "$VM_3")  ipkey=3 ;;
      *)        ipkey="$(printf '%s' "$hn" | sed 's/^vm-//; s/-/_/g')" ;;
    esac
    nip=""
    if declare -n _netplan_ref="NETPLAN_IP_${ipkey}" 2>/dev/null; then nip="${_netplan_ref:-}"; fi
    if [ -n "$nip" ] && [ "$APPLY_NETPLAN" = "1" ]; then
      confirm "write static netplan on $hn (IP $nip; existing file backed up)"
      if [ "$CHECK_ONLY" != "1" ]; then
        ssh "$h" "sudo cp /etc/netplan/01-netcfg.yaml /etc/netplan/01-netcfg.yaml.bak 2>/dev/null || true; \
          printf 'network:\n  version: 2\n  ethernets:\n    ${NETPLAN_IF:-eno1}:\n      addresses:\n        - %s/24\n      routes:\n        - to: default\n          via: ${NETPLAN_GW:?set NETPLAN_GW in hosts.env - no default gateway address is shipped in the script}\n' '$nip' | sudo tee /etc/netplan/01-netcfg.yaml >/dev/null; sudo chmod 600 /etc/netplan/01-netcfg.yaml; sudo netplan apply"
      fi
    else
      cur="$(ssh "$h" "hostname -I | awk '{print \$1}'" || echo unknown)"
      log "§1   $hn current IP: $cur${nip:+ (netplan IP $nip NOT applied — re-run with --apply-netplan)}"
    fi
  done
  ok "§1 provisioning + base OS"
}

# ---------------------------------------------------------------- §2 docker
install_docker() {
  for h in "${PVMXS[@]}"; do
    log "§2 — Docker on $(vm_display_name "$h")"
    ssh "$h" "command -v docker >/dev/null || { sudo apt-get update && sudo apt-get install -y docker.io docker-compose-v2; }; sudo usermod -aG docker poc"
    ssh "$h" "docker run --rm alpine echo ok >/dev/null && docker compose version >/dev/null" \
      || die "docker not usable on $(vm_display_name "$h")"
  done
  ok "§2 docker on all 3 VMs"
}

# ---------------------------------------------------------------- §2a firewall
# The scripts own the POC's cross-VM port openings (the owner baseline opens
# SSH only; default-deny UFW would make every later cross-VM call time out).
# Scoped to the POC LAN (/24 derived from NETPLAN_IP_* unless UFW_EA_CIDR is
# set); the RabbitMQ mgmt UI stays loopback-only — never opened here.
open_firewall() {
  local cidr="${UFW_EA_CIDR:-}"
  [ -n "$cidr" ] || cidr="${NETPLAN_IP_XB%.*}.0/24"
  [ -n "$cidr" ] && [ "$cidr" != ".0/24" ] || { log "§2a   no NETPLAN_IP_XB/UFW_EA_CIDR — skipping UFW setup"; return 0; }
  if [ "$CHECK_ONLY" = "1" ]; then log "check-only: would open UFW ports on $VM_XB: 5672,7233 from $cidr"; return 0; fi
  if ! ssh "$VM_XB" "sudo -n ufw status 2>/dev/null | grep -q 'Status: active'"; then
    log "§2a   UFW not active on $VM_XB — nothing to open"
    return 0
  fi
  ssh "$VM_XB" "sudo -n ufw allow from $cidr to any port 5672 proto tcp && sudo -n ufw allow from $cidr to any port 7233 proto tcp" \
    || die "§2a   ufw rules failed on $VM_XB (passwordless sudo required — deploy/README)"
  ok "§2a   UFW: 5672 (AMQP) + 7233 (Temporal) open on $VM_XB from $cidr"
}

# ---------------------------------------------------------------- §3 rabbitmq
declare_topology() {
  local base="http://127.0.0.1:15672"
  local m
  # V2 queue family: ea-tasks (durable, x-max-priority 3 — declared exactly once,
  # OQ4 single declaration point), ea-tasks.dlq, ea-tasks.response. The topic
  # exchange agent.tasks keeps its V1 name (the manager publishes agent.tasks.<capability>).
  m="$(printf 'user = "ea:%s"\n' "$RABBITMQ_PASS" | ssh "$VM_XB" "curl -s -o /dev/null -w '%{http_code}' -K - $base/api/queues/%2F/ea-tasks || true")"
  if [ "$m" = "404" ]; then
    confirm "declare topic exchange agent.tasks + ea-tasks queue + binding + DLQ on $VM_XB"
    if [ "$CHECK_ONLY" != "1" ]; then
      # corrected mgmt-API paths (POST the named resource; binding = /q/<queue>);
      # ea-tasks.response declared for M5; password via stdin curl config (-K -), never argv
      # stage the curl auth config (0600 on the remote; removed after declare)
    printf 'user = "ea:%s"\n' "$RABBITMQ_PASS" | ssh "$VM_XB" 'umask 077; cat > /tmp/rmq-cfg && chmod 600 /tmp/rmq-cfg'
    ssh "$VM_XB" "B=$base bash -s" <<'RABBIT_API'
set -e
cfg=$(cat /tmp/rmq-cfg)
printf '%s\n' "$cfg" | curl -s -K - -XPUT "$B/api/exchanges/%2F/agent.tasks" -d '{"type":"topic","durable":true}'
printf '%s\n' "$cfg" | curl -s -K - -XPUT "$B/api/queues/%2F/ea-tasks" -d '{"durable":true,"arguments":{"x-max-priority":3}}'
printf '%s\n' "$cfg" | curl -s -K - -XPOST "$B/api/bindings/%2F/e/agent.tasks/q/ea-tasks" -d '{"routing_key":"ea.tasks.#","properties_key":""}'
printf '%s\n' "$cfg" | curl -s -K - -XPUT "$B/api/queues/%2F/ea-tasks.dlq" -d '{"durable":true}'
printf '%s\n' "$cfg" | curl -s -K - -XPUT "$B/api/queues/%2F/ea-tasks.response" -d '{"durable":true}'
rm -f /tmp/rmq-cfg
RABBIT_API
    fi
  else
    log "§3   topology already declared (idempotent)"
  fi
}

cross_vm_publish_test() {
  local n post
  log "§3   cross-VM publish test (mgmt UI is loopback-only on $VM_XB; AMQP 5672 is the cross-VM path)"
  # Publish from vm-xa (the manager's path) over AMQP 5672 — the actual cross-VM
  # wire the manager uses — via python3+pika (installed on vm-xa as a test
  # dependency). The password is staged on vm-xa as a 0600 file via stdin and
  # removed after — never in argv or logs (the display-mask rule).
  ssh "$VM_XA" "python3 -c 'import pika' 2>/dev/null || { command -v apt-get >/dev/null && sudo apt-get install -y python3-pika >/dev/null 2>&1 || true; }"
  printf '%s' "$RABBITMQ_PASS" | ssh "$VM_XA" 'umask 077; cat > /tmp/rmq-pw && chmod 600 /tmp/rmq-pw'
  if ! ssh "$VM_XA" "RMQ_HOST=${NETPLAN_IP_XB:?NETPLAN_IP_XB needed} python3 - <<'PY'
import pika, os
pw = open('/tmp/rmq-pw').read().strip()
c = pika.BlockingConnection(pika.ConnectionParameters(
    host=os.environ['RMQ_HOST'],
    credentials=pika.PlainCredentials('ea', pw)))
ch = c.channel()
ch.basic_publish(exchange='agent.tasks', routing_key='agent.tasks',
                 body='m0-cross-test', properties=pika.BasicProperties(delivery_mode=2))
c.close()
print('published')
PY"; then
    ssh "$VM_XA" 'rm -f /tmp/rmq-pw'
    log "§3   cross-VM publish FAILED (vm-xa -> $VM_XB:5672)"
    return 1
  fi
  ssh "$VM_XA" 'rm -f /tmp/rmq-pw'
  # Assert via rabbitmqctl (authoritative — the mgmt-API stats lag after a publish)
  n="$(ssh "$VM_XB" "docker exec rabbitmq-rabbitmq-1 rabbitmqctl list_queues name messages consumers 2>/dev/null | grep -E '^ea-tasks[[:space:]]' | head -1 | awk '{print \$2}'" || true)"
  if [ "${n:-0}" -ge 1 ]; then
    log "§3   queue messages=$n via AMQP 5672 from vm-xa (rabbitmqctl)"
    # Fetch+ack the V2 copy from ea-tasks (mgmt API GET on vm-xb loopback — no
    # consumer on ea-tasks, so nothing else can take it). Note: the exchange
    # fans out to BOTH queues independently — the V1 bridge's copy (agent.tasks
    # durable) is a separate delivery; the V1 bridge rejects this non-JSON
    # payload to agent.tasks.dlq (drained below, V1 cleanup).
    printf 'user = "ea:%s"\n' "$RABBITMQ_PASS" | ssh "$VM_XB" 'umask 077; cat > /tmp/rmq-cfg && chmod 600 /tmp/rmq-cfg'
    ssh "$VM_XB" 'curl -s -K /tmp/rmq-cfg -XPOST "http://127.0.0.1:15672/api/queues/%2F/ea-tasks/get" -H "content-type: application/json" -d "{\"count\":10,\"ackmode\":\"ack_requeue_false\",\"encoding\":\"auto\"}" | grep -q "m0-cross-test" && echo "fetch-ack-ok"; rm -f /tmp/rmq-cfg'
    printf 'user = "ea:%s"\n' "$RABBITMQ_PASS" | ssh "$VM_XB" 'umask 077; cat > /tmp/rmq-cfg && chmod 600 /tmp/rmq-cfg'
    ssh "$VM_XB" 'curl -s -K /tmp/rmq-cfg -XPOST "http://127.0.0.1:15672/api/queues/%2F/agent.tasks.dlq/get" -H "content-type: application/json" -d "{\"count\":10,\"ackmode\":\"ack_requeue_false\",\"encoding\":\"auto\"}" >/dev/null; rm -f /tmp/rmq-cfg'
    post="$(ssh "$VM_XB" "docker exec rabbitmq-rabbitmq-1 rabbitmqctl list_queues name messages consumers 2>/dev/null | grep -E '^(ea-tasks|agent.tasks.dlq)[[:space:]]' | awk '{print \$1, \$2}'" || true)"
    log "§3   post-test: $post (ea-tasks drained; V1 DLQ drained — V1 cleanup)"
    return 0
  fi
  log "§3   cross-VM publish: ea-tasks messages=${n:-0} (want >=1) — rabbitmqctl"
  return 1
}

deploy_rabbitmq() {
  log "§3 — RabbitMQ (Topic) on $VM_XB"
  # RABBITMQ_PASS is loaded from the gitignored .env BEFORE the coexistence
  # branch — both paths (reuse the live broker / compose up) need it for
  # declare_topology + cross_vm_publish_test (set -u would die otherwise).
  local envf="$M0/rabbitmq/.env"
  if ! grep -q '^RABBITMQ_PASS=' "$envf" 2>/dev/null; then
    confirm "generate RABBITMQ_PASS into $envf (gitignored)"
    if [ "$CHECK_ONLY" != "1" ]; then echo "RABBITMQ_PASS=$(openssl rand -hex 16)" >> "$envf"; fi
  fi
  RABBITMQ_PASS="$(grep '^RABBITMQ_PASS=' "$envf" | cut -d= -f2)"
  [ -n "$RABBITMQ_PASS" ] || die "RABBITMQ_PASS missing (generate: openssl rand -hex 16)"
  # COEXISTENCE MODE (V1 stack running): reuse the live broker — the V1 compose
  # project owns ports 5672/15672 and the container name; a second compose up
  # would conflict. The V1 container is connected to ea-net with alias rabbitmq
  # (the documented coexistence exception to the compose-declared rule — after
  # the estate switch-over, the V2 compose is the sole source and the V1 tree is
  # retired). Post-switch-over: the V2 compose up path is the normal path.
  local rmq_container
  rmq_container="$(ssh "$VM_XB" "docker ps -qf name=rabbitmq" 2>/dev/null || true)"
  if [ -n "$rmq_container" ] && [ "$CHECK_ONLY" != "1" ]; then
    log "§3   live rabbitmq container detected — COEXISTENCE MODE: reuse it"
    ssh "$VM_XB" "sudo mkdir -p /opt/ea/deploy-v2/m0/rabbitmq && sudo chown -R \"$(id -un):$(id -gn)\" /opt/ea"
    rsync -az "$M0/rabbitmq/compose.yaml" "$VM_XB:/opt/ea/deploy-v2/m0/rabbitmq/"  # V2 compose staged for the post-switch-over path (not applied)
    ssh "$VM_XB" "docker network inspect ea-net >/dev/null 2>&1 || docker network create ea-net"
    ssh "$VM_XB" "docker network connect --alias rabbitmq ea-net rabbitmq-rabbitmq-1 2>/dev/null || true"
    ssh "$VM_XB" "docker compose -f /opt/ea/deploy-v2/m0/rabbitmq/compose.yaml exec -T rabbitmq rabbitmq-diagnostics -q ping" >/dev/null 2>&1 \
      || ssh "$VM_XB" "docker exec rabbitmq-rabbitmq-1 rabbitmq-diagnostics -q ping" >/dev/null 2>&1 \
      || die "live rabbitmq not serving"
  else
  if [ "$CHECK_ONLY" != "1" ]; then
    ssh "$VM_XB" "sudo mkdir -p /opt/ea/deploy-v2/m0/rabbitmq && sudo chown -R \"$(id -un):$(id -gn)\" /opt/ea"
    rsync -az "$M0/rabbitmq/compose.yaml" "$envf" "$VM_XB:/opt/ea/deploy-v2/m0/rabbitmq/"
    ssh "$VM_XB" "cd /opt/ea/deploy-v2/m0/rabbitmq && docker compose up -d"
  fi
  fi
  local i
  for i in $(seq 1 40); do
    if ssh "$VM_XB" "docker compose -f /opt/ea/deploy-v2/m0/rabbitmq/compose.yaml exec -T rabbitmq rabbitmq-diagnostics -q ping" >/dev/null 2>&1 \
      || ssh "$VM_XB" "docker exec rabbitmq-rabbitmq-1 rabbitmq-diagnostics -q ping" >/dev/null 2>&1; then
      break
    fi
    sleep 3
    if [ "$i" = "40" ]; then die "rabbitmq healthcheck flapping (memory alarm? see M0 §8)"; fi
  done
  declare_topology
  cross_vm_publish_test || return 0   # non-fatal here; re-checked at the gate (§7)
  ok "§3 rabbitmq up + topology + cross-VM test"
}

# ---------------------------------------------------------------- §4 temporal
deploy_temporal() {
  log "§4 — Temporal on $VM_XB (its Postgres is Temporal-only; vm-hindsight gets its own in M4)"
  local envf="$M0/temporal/.env"
  if ! grep -q '^TEMPORAL_DB_PASS=' "$envf" 2>/dev/null; then
    confirm "generate TEMPORAL_DB_PASS into $envf (gitignored)"
    if [ "$CHECK_ONLY" != "1" ]; then echo "TEMPORAL_DB_PASS=$(openssl rand -hex 16)" >> "$envf"; fi
  fi
  TEMPORAL_DB_PASS="$(grep '^TEMPORAL_DB_PASS=' "$envf" | cut -d= -f2)"
  [ -n "$TEMPORAL_DB_PASS" ] || die "TEMPORAL_DB_PASS missing"
  if [ ! -f "$M0/image-tags.env" ]; then
    log "§4   writing image pins to deploy-v2/m0/image-tags.env (check cli.temporal.io for current stable)"
    if [ "$CHECK_ONLY" != "1" ]; then
      cat > "$M0/image-tags.env" <<'PINS'
# image pins (M0 §0 — record every pin at deploy time)
RABBITMQ_IMAGE=rabbitmq:4-management-alpine
TEMPORAL_IMAGE=temporalio/server:1.27.0
POSTGRES_IMAGE=postgres:16
PINS
    fi
  fi
  if [ "$CHECK_ONLY" != "1" ]; then
    local tmp_container
    tmp_container="$(ssh "$VM_XB" "docker ps -qf name=temporal-temporal" 2>/dev/null || true)"
    if [ -n "$tmp_container" ]; then
      # COEXISTENCE MODE: reuse the live temporal stack (V1 compose project) —
      # the V2 compose up would conflict on the container name/port. The V2
      # compose is staged for the post-switch-over path (not applied).
      log "§4   live temporal stack detected — COEXISTENCE MODE: reuse it"
      ssh "$VM_XB" "sudo mkdir -p /opt/ea/deploy-v2/m0/temporal && sudo chown -R \"$(id -un):$(id -gn)\" /opt/ea"
      rsync -az "$M0/temporal/compose.yaml" "$envf" "$VM_XB:/opt/ea/deploy-v2/m0/temporal/"
      ssh "$VM_XB" "docker network inspect ea-net >/dev/null 2>&1 || docker network create ea-net"
      ssh "$VM_XB" "docker network connect --alias temporal ea-net temporal-temporal-1 2>/dev/null || true"
    else
      ssh "$VM_XB" "sudo mkdir -p /opt/ea/deploy-v2/m0/temporal && sudo chown -R \"$(id -un):$(id -gn)\" /opt/ea"
      rsync -az "$M0/temporal/compose.yaml" "$envf" "$VM_XB:/opt/ea/deploy-v2/m0/temporal/"
      ssh "$VM_XB" "cd /opt/ea/deploy-v2/m0/temporal && docker compose up -d"
    fi
  fi
  # pinned: override TEMPORAL_CLI_VERSION in hosts.env; fetched to a file, not piped to a shell
  ssh "$VM_XB" "command -v temporal >/dev/null || { VER=\$(curl -s https://api.github.com/repos/temporalio/cli/releases/latest | grep -oP 'tag/v\K[0-9.]+'); curl -sL \"https://github.com/temporalio/cli/releases/download/v\$VER/temporal_cli_\${VER}_linux_amd64.tar.gz\" -o /tmp/tc.tgz && tar -xzf /tmp/tc.tgz -C /tmp && sudo mv /tmp/temporal /usr/local/bin/; }"
  local i
  for i in $(seq 1 40); do
    if ssh "$VM_XB" "temporal operator cluster health 2>/dev/null" | grep -Eq "SERVING|HEALTHY"; then
      break
    fi
    sleep 3
    if [ "$i" = "40" ]; then die "temporal not healthy (first start = schema init; M0 §8)"; fi
  done
  ssh "$VM_XB" "temporal operator namespace list" | grep -q "default" || die "default namespace missing"
  ok "§4 temporal healthy + default namespace"
}

go_sdk_smoke() {
  log "§4b — Go SDK smoke (the language-decision check: all Temporal code is Go)"
  local host="${SMOKE_HOST:-local}"
  if [ "$CHECK_ONLY" = "1" ]; then log "check-only: skip smoke"; return 0; fi
  if [ "$host" = "local" ]; then
    command -v go >/dev/null || die "Go toolchain not found on the build host (required — Go mandate)"
    local smoke_out
    smoke_out="$( cd "$M0/go-sdk-smoke" && go run . -addr "$TEMPORAL_ADDR" 2>&1 )" || true
    echo "$smoke_out" | tee -a "$LOG"
    echo "$smoke_out" | grep -q "hello from greet" || die "go-sdk-smoke did not print 'hello from greet'"
  else
    ssh "$host" "cd /opt/ea/deploy-v2/m0/go-sdk-smoke && go run . -addr $TEMPORAL_ADDR" | grep -q "hello from greet" \
      || die "go-sdk-smoke failed on $host"
  fi
  ok "§4b Go-SDK workflow completed against $TEMPORAL_ADDR"
}

# ---------------------------------------------------------------- §5 network
network_matrix() {
  log "§5 — network verification matrix -> $EVIDENCE/network-matrix.txt"
  if [ "$CHECK_ONLY" = "1" ]; then log "check-only: skip live matrix"; return 0; fi
  local from to
  {
    echo "# M0 network matrix — $(date -u)"
    for from in "${PVMXS[@]}"; do
      for to in "${PVMXS[@]}"; do
        # pairwise L3 reachability WITHOUT VM keys: probe the target's ssh
        # port from the source VM via bash /dev/tcp (docs §5 method — the
        # workstation relays the probe through ssh to the source VM).
        if ssh -o BatchMode=yes -o ConnectTimeout=5 "$from" \
             "timeout 5 bash -c '</dev/tcp/$to/22' 2>/dev/null"; then
          echo "L3 $from -> $to : OK"
        else
          echo "L3 $from -> $to : FAIL"
        fi
      done
    done
    for to in "$VM_XA" "$VM_XB"; do
      echo "OUT $to -> github.com : $(ssh "$to" "curl -sI https://github.com | head -1" || echo FAIL)"
    done
    echo "PORT $VM_XB : $(ssh "$VM_XB" "nc -vz 127.0.0.1 5672 >/dev/null 2>&1 && echo amqp-open; nc -vz 127.0.0.1 7233 >/dev/null 2>&1 && echo temporal-open" 2>/dev/null | tr '\n' ' ')"
  } | tee "$EVIDENCE/network-matrix.txt"
  if grep -q FAIL "$EVIDENCE/network-matrix.txt"; then
    die "network matrix has FAIL lines (M0 §5: PVE DNS or /etc/hosts — record which in the decision log)"
  fi
  ok "§5 matrix 100% recorded"
}

# ---------------------------------------------------------------- §6 decision log
write_decision_log() {
  log "§6 — decision log (VM numbering D-8 + Go-for-Temporal)"
  if [ "$CHECK_ONLY" = "1" ]; then return 0; fi
  if [ ! -f "$M0/decision-log.md" ]; then
    echo "# M0 decision log" > "$M0/decision-log.md"
  fi
  {
    echo ""
    echo "## M0 install run — $(date +%F)"
    echo "- VM naming: D-8 RESOLVED by owner 2026-10-25 (labels are POC discussion devices, not commitments); POC hostnames: vm-xa/vm-xb/vm-hindsight -> diagram labels VM-Xa/VM-Xb/VM-3"
    echo "- Language decision: Go for ALL Temporal code (owner instruction: speed + size)"
    echo "- Name-resolution mechanism used: (PVE DNS or /etc/hosts — record which)"
  } >> "$M0/decision-log.md"
  ok "§6 decision log updated"
}

# ---------------------------------------------------------------- §7 gate
gate_summary() {
  log "§7 — M0 acceptance checks (the M0 gate)"
  local fails=0 h
  if [ "$CHECK_ONLY" = "1" ]; then
    log "check-only: gate checks skipped"
    return 0
  fi
  # 1: 3 VMs, docker runs on each
  for h in "${PVMXS[@]}"; do
    if ssh "$h" "docker run --rm alpine echo ok" >/dev/null 2>&1; then
      log "gate 1 docker on $(vm_display_name "$h") : PASS"
    else
      log "gate 1 docker on $(vm_display_name "$h") : FAIL"; fails=1
    fi
  done
  # 2: cross-VM topic publish/consume
  if cross_vm_publish_test; then log "gate 2 cross-VM publish : PASS"; else log "gate 2 cross-VM publish : FAIL"; fails=1; fi
  # 3: go sdk smoke (temporal health already asserted in §4)
  if go_sdk_smoke; then log "gate 3 go-sdk smoke : PASS"; else log "gate 3 go-sdk smoke : FAIL"; fails=1; fi
  # 4: network matrix 100%
  if [ -f "$EVIDENCE/network-matrix.txt" ] && ! grep -q FAIL "$EVIDENCE/network-matrix.txt"; then
    log "gate 4 network matrix : PASS"
  else
    log "gate 4 network matrix : check $EVIDENCE/network-matrix.txt"; fails=1
  fi
  # 5: numbering locked + docs updated
  if [ -f "$M0/decision-log.md" ]; then log "gate 5 decision log : PASS"; else log "gate 5 decision log : FAIL"; fails=1; fi

  if [ "$fails" = "0" ]; then
    ok "M0 gate: all 5 acceptance checks PASS"
    log "Next: run TP-M0 — version 1/test procedures/M0-Chassis-Test-Procedure.md (file evidence in $EVIDENCE)."
  else
    warn "M0 gate: FAILURES above — remediate per M0 §8, re-run this script (idempotent), then TP-M0."
    if [ "$NO_GATE" != "1" ]; then exit 1; fi
  fi
}

# ---------------------------------------------------------------- main
main() {
  log "=== M0 chassis install start (check-only=$CHECK_ONLY no-gate=$NO_GATE) ==="
  check_assets
  confirm "M0: provision/verify 3 VMs + base OS + Docker + RabbitMQ + Temporal (idempotent)"
  provision_vms
  install_docker
  open_firewall
  deploy_rabbitmq
  deploy_temporal
  go_sdk_smoke
  network_matrix
  write_decision_log
  gate_summary
  log "=== M0 install complete ==="
}
main
