#!/usr/bin/env bash
# M1 — stage the OpenRouter key for the CoS profile: read it from vm-xb's
# staged m3.env, write it to the ea-m5 .env on vm-xa, never print it.
set -euo pipefail
val="$(ssh vm-xb "sudo grep -oE '^ANTHROPIC_API_KEY=.*' /opt/ea/secrets/m3.env" | head -1 | cut -d= -f2-)"
[ -n "$val" ] || { echo "key not found in m3.env"; exit 1; }
grep -q '^OPENROUTER_API_KEY=' /opt/ea/deploy-v2/m5/.env || echo "OPENROUTER_API_KEY=$val" >> /opt/ea/deploy-v2/m5/.env
chmod 600 /opt/ea/deploy-v2/m5/.env
grep -q '^OPENROUTER_API_KEY=' /opt/ea/deploy-v2/m5/.env && echo "staged (value not displayed)"
