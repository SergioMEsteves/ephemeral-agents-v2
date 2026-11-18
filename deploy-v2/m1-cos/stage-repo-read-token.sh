#!/usr/bin/env bash
# M1 §5 amendment (ledger 16) — stage the CoS repo READ credential:
#   usage: stage-repo-read-token.sh <file-with-raw-PAT>
# The file holds the fine-grained PAT (Contents:Read, project repos) on ONE
# line, created by the owner locally. The value is never printed.
set -euo pipefail
TOKEN_FILE="${1:?usage: stage-repo-read-token.sh <file-with-raw-PAT>}"
[ -s "$TOKEN_FILE" ] || { echo "token file empty/missing"; exit 1; }
val="$(tr -d '[:space:]' < "$TOKEN_FILE")"
[ -n "$val" ] || { echo "empty token"; exit 1; }
printf 'https://arvisdev:%s@github.com\n' "$val" | sudo tee /opt/ea/cos/profile/git-credentials >/dev/null
sudo chmod 600 /opt/ea/cos/profile/git-credentials
sudo sh -c 'echo "staged (value not displayed)"; wc -c < /opt/ea/cos/profile/git-credentials' 
