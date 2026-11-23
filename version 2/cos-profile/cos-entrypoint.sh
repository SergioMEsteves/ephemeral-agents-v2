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
git config --global credential.helper store   # /root/.git-credentials (mounted, read-only)
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

# 2. the resident backend — `hermes serve --host 0.0.0.0` (the desktop's
# remote-connection server; public binds REQUIRE an auth provider —
# HERMES_DASHBOARD_SESSION_TOKEN is the bundled session-token provider that
# authorizes the Desktop's remote-gateway 'Session token' field).
# --skip-build: the container has no web-UI build step; serve the existing dist.
hermes profile list 2>/dev/null | grep -q "cos " || hermes profile create cos --description "Chief of Staff — proposes, owner disposes" >/dev/null
cp /profile/AGENTS.md "${HERMES_HOME:-/root/.hermes}/profiles/cos/AGENTS.md"   # the CoS prompt IS the profile; HERMES_HOME=/state keeps the board durable (D12)
hermes profile use cos >/dev/null                            # sticky default profile
hermes config set model.default z-ai/glm-5.3-flash >/dev/null
hermes config set model.provider openrouter >/dev/null
# the default profile (what `serve` binds as its base) gets the same model —
# GLM 5.3 Flash is the VM-Xa default, not just the CoS profile's.
hermes -p default config set model.default z-ai/glm-5.3-flash >/dev/null
hermes -p default config set model.provider openrouter >/dev/null
# key staging: the CLI resolves provider keys from env files (profile .env and
# $HERMES_HOME/.env), NOT the process env — mirror the compose-staged
# OPENROUTER_API_KEY into both, or chat sessions fail with
# ProviderNotConfiguredError even though `serve` itself works.
stage_key() {
  if ! grep -q '^OPENROUTER_API_KEY=' "$1" 2>/dev/null && [ -n "${OPENROUTER_API_KEY:-}" ]; then
    printf 'OPENROUTER_API_KEY=%s\n' "$OPENROUTER_API_KEY" >> "$1"
  fi
}
stage_key /root/.hermes/.env
stage_key /root/.hermes/profiles/cos/.env

exec hermes serve --host 0.0.0.0 --port 8080 --skip-build
