#!/usr/bin/env bash
# M1 §2b — stage the CoS four-item credential allow-list in the ea-m5 .env
# (values generated here, never printed; file stays 0600, gitignored).
set -euo pipefail
ENVF="${1:-/opt/ea/deploy-v2/m5/.env}"
[ -f "$ENVF" ] || { echo "no env file at $ENVF"; exit 1; }
gen() { head -c 24 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32; }
for k in LLM_PROXY_COS_TOKEN COS_SESSION_TOKEN COS_API_TOKEN HINDSIGHT_WRITE_TOKEN; do
  grep -q "^$k=" "$ENVF" || echo "$k=$(gen)" >> "$ENVF"
done
chmod 600 "$ENVF"
echo "staged: LLM_PROXY_COS_TOKEN COS_SESSION_TOKEN COS_API_TOKEN HINDSIGHT_WRITE_TOKEN ($(grep -c = "$ENVF") total keys)"
