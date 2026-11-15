#!/usr/bin/env bash
# CoS entrypoint — persistent-profile variant of the executor hydration
# contract (M1 §4): the FIRST persistent consumer. Boots, hydrates
# (roster persona — already checked out at /work/roster, llm-wiki,
# Hindsight pointers), self-reports, then starts the Hermes gateway with
# the CoS AGENTS.md loaded. Reboot-safe: restart: unless-stopped in the
# compose; the board state lives in /state (bind mount, D12).
set -u
export PATH="/root/.local/bin:$PATH"   # the installer puts the hermes CLI here

TASK_ID="cos-resident-$(date -u +%Y%m%d)"
START_MS="$(date +%s%3N)"

echo "{\"event\":\"boot\",\"task_id\":\"$TASK_ID\"}"

# 1. hydration — roster persona is bind-mounted (read-only); llm-wiki + hindsight per the executor contract
LLM_WIKI="${LLM_WIKI_DIR:-/work/llm-wiki}"
mkdir -p "$LLM_WIKI"
git -C "$LLM_WIKI" fetch --depth 1 origin main 2>/dev/null || git clone --depth 1 https://github.com/arvisdev/llm-wiki.git "$LLM_WIKI" 2>/dev/null || echo "{\"event\":\"wiki-degrade\",\"reason\":\"clone unavailable — graceful\"}"

# hindsight pointer write (CoS write class) — one boot pointer
if [ -n "${HINDSIGHT_URL:-}" ] && [ -n "${HINDSIGHT_WRITE_TOKEN:-}" ]; then
  curl -sf --max-time 10 -XPOST "$HINDSIGHT_URL/memory/write" \
    -H "content-type: application/json" -H "Authorization: Bearer $HINDSIGHT_WRITE_TOKEN" \
    -d "{\"task_id\":\"$TASK_ID\",\"scope\":\"cos-boot\",\"body\":{\"summary\":\"CoS profile booted\"}}" >/dev/null 2>&1 || true
fi

BOOT_MS=$(( $(date +%s%3N) - START_MS ))
echo "{\"event\":\"self-report\",\"task_id\":\"$TASK_ID\",\"boot_ms\":$BOOT_MS,\"sources\":{\"agent_repo\":true,\"llm-wiki\":\"$([ -d "$LLM_WIKI/.git" ] && echo true || echo degraded)\",\"hindsight\":\"$([ -n "${HINDSIGHT_URL:-}" ] && echo true || echo false)\"}}"

# 2. the resident backend — `hermes serve` (the desktop's remote-connection
# server per the S7 runbook procedure), NOT `gateway run` (that serves
# messaging platforms: Telegram/Discord/... — not the desktop protocol)
exec hermes serve
