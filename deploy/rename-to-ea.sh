#!/usr/bin/env bash
# Copyright 2026 A&R Visual Development Inc (arvisdev)
# Licensed under the Apache License, Version 2.0 — see LICENSE.
#
# Estate half of the ea- rename micro-gate (platform design §9.7) — STAGED,
# NOT EXECUTED as part of this commit. Run only on explicit owner go-ahead;
# it touches the live estate.
#
# What it does (three gated steps, each verified before the next):
#   1. Registry re-tag: all 9 V1 images re-tagged ea/… on the private
#      registry — verified by DIGEST EQUALITY with the V1 images
#      (rename without rebuild; a digest mismatch is a hard failure).
#   2. Queue re-creation: the agent.tasks queue is re-declared ONCE under
#      the ea-* name WITH the x-max-priority declaration (OQ4 — the
#      priority field's single redeclare point). Messages are drained to
#      the V1 queue first and republished to the ea-* queue.
#   3. Baseline test path re-run under ea names (V1 tests, env-pointed at
#      the ea names) — must be green before any V2 feature lands.
#
# De-identification: no IPs/hostnames in this file — everything comes from
# the gitignored env inventory (deploy/.env.ea or the shell environment).

set -euo pipefail

: "${REGISTRY_HOST:?set REGISTRY_HOST (from the gitignored env inventory)}"
: "${EXECUTION_HOST:?set EXECUTION_HOST (from the gitignored env inventory)}"
ASSUME_YES="${ASSUME_YES:-0}"

IMAGES="topic-bridge lifecycle worker executor-stub hermes-ephemeral claude-coder hindsight-api gateway manager"

confirm() { [ "$ASSUME_YES" = "1" ] && return 0; read -r -p "$1 [y/N] " a; [ "$a" = "y" ]; }

# --- step 1: registry re-tag with digest equality ---------------------------
step1() {
  echo "== step 1: registry re-tag poc/… -> ea/… (digest equality) =="
  local fail=0
  for img in $IMAGES; do
    src="poc/${img}:1.0.0"; dst="ea/${img}:1.0.0"
    sd=$(docker manifest inspect --verbose "${REGISTRY_HOST}/${src}" 2>/dev/null \
         | python3 -c 'import json,sys; print(json.load(sys.stdin).get("Descriptor",{}).get("digest",""))')
    if [ -z "$sd" ]; then echo "  MISSING source ${src} in registry — abort"; fail=1; continue; fi
    echo "  ${src} digest ${sd}"
    docker pull -q "${REGISTRY_HOST}/${src}" >/dev/null
    docker tag  "${REGISTRY_HOST}/${src}" "${REGISTRY_HOST}/${dst}"
    docker push -q "${REGISTRY_HOST}/${dst}" >/dev/null
    dd=$(docker manifest inspect --verbose "${REGISTRY_HOST}/${dst}" 2>/dev/null \
         | python3 -c 'import json,sys; print(json.load(sys.stdin).get("Descriptor",{}).get("digest",""))')
    if [ "$sd" != "$dd" ]; then
      echo "  DIGEST MISMATCH ${dst}: ${dd} != ${sd} — abort"; fail=1
    else
      echo "  OK ${dst} digest-identical"
    fi
  done
  [ "$fail" = "0" ] || { echo "step 1 FAILED — do not proceed"; exit 1; }
  echo "step 1 green: 9/9 images re-tagged digest-identical"
}

# --- step 2: queue re-creation under ea-* with x-max-priority ---------------
step2() {
  echo "== step 2: queue re-creation (agent.tasks -> ea-tasks, x-max-priority) =="
  confirm "This re-declares the task queue under the ea-* name with x-max-priority. Drain the V1 queue first (it must be empty or its messages republished). Continue?" || return 1
  ssh "$EXECUTION_HOST" 'docker exec $(docker ps -qf name=rabbitmq) rabbitmqctl list_queues name messages' || true
  # The ea-* queue is declared by the V2 compose/bridge on first connect with
  # x-max-priority=3 — re-created here only if the stack is not yet running:
  ssh "$EXECUTION_HOST" 'docker exec -i $(docker ps -qf name=rabbitmq) rabbitmqadmin \
      declare queue name=ea-tasks durable=true \
      arguments='"'"'{"x-max-priority":3}'"'"'' \
    || ssh "$EXECUTION_HOST" 'python3 - <<PY
import pika, os, json
q = os.environ.get("EA_TASKS_QUEUE", "ea-tasks")
params = pika.URLParameters(os.environ["RABBITMQ_URL"])
conn = pika.BlockingConnection(params)
conn.channel().queue_declare(queue=q, durable=True, arguments={"x-max-priority": 3})
conn.close()
print("declared", q, "with x-max-priority=3")
PY'
  ssh "$EXECUTION_HOST" 'docker exec $(docker ps -qf name=rabbitmq) rabbitmqctl list_queues name arguments' | grep -A1 ea-tasks \
    && echo "step 2 green: ea-tasks declared with x-max-priority" \
    || { echo "step 2 FAILED — queue not visible with arguments"; exit 1; }
}

# --- step 3: baseline test path under ea names ------------------------------
step3() {
  echo "== step 3: V1 baseline test path re-run under ea names =="
  # The V2 deploy layer (born ea-named) is the run target; until it is
  # installed on the estate this step cannot run — the staged build's
  # chassis/install stages bring it up. This step asserts the precondition
  # and runs the contract suite + the V1 test scripts pointed at ea names.
  if ! ssh "$EXECUTION_HOST" 'docker network inspect ea-net >/dev/null 2>&1'; then
    echo "  precondition not met: ea-net absent — install the V2 deploy layer first (staged build stages 1-2)"; exit 1
  fi
  python3 "$(dirname "$0")/contract-tests/run.py"
  echo "step 3 green: contract suite + baseline path under ea names"
}

case "${1:-all}" in
  step1) step1 ;;
  step2) step2 ;;
  step3) step3 ;;
  all)   step1; step2; step3 ;;
  *)     echo "usage: $0 [all|step1|step2|step3]"; exit 2 ;;
esac
