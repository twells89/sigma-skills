#!/usr/bin/env bash
# Exchange Sigma credentials for a bearer token.
# Usage:  eval "$(scripts/get-token.sh)"
# Sets SIGMA_API_TOKEN in the calling shell.
#
# Two auth options (SIGMA_BASE_URL is required for both):
#   - Client credentials: set SIGMA_CLIENT_ID / SIGMA_CLIENT_SECRET (headless).
#   - Browser login: if those are unset, this delegates to get_token.py, which
#     redeems the refresh token the sigma-api skill's browser-login.sh stored
#     in your OS keychain — no client ID/secret needed.
#
# bash/zsh only — PowerShell and cmd.exe can't run `eval "$(...)"`. For a
# shell-neutral path (any shell, any agent), use scripts/get_token.py instead:
#   python3 scripts/get_token.py --workdir /tmp/my-run
# which writes auth.json for scripts/lib/sigma_rest.rb to pick up automatically.

set -euo pipefail

: "${SIGMA_BASE_URL:?Set SIGMA_BASE_URL to your cloud API host (see the README Auth section)}"

# No client credentials → hand off to get_token.py, which covers the
# browser-login refresh path too (and prints the same `export` line).
if [ -z "${SIGMA_CLIENT_ID:-}" ] || [ -z "${SIGMA_CLIENT_SECRET:-}" ]; then
  SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
  if command -v python3 >/dev/null 2>&1; then
    exec python3 "$SCRIPT_DIR/get_token.py" --print-export
  fi
  echo "Error: SIGMA_CLIENT_ID / SIGMA_CLIENT_SECRET are unset and python3 is not available." >&2
  echo "  Set client credentials, or sign in with the sigma-api skill's browser-login.sh." >&2
  exit 1
fi

CREDENTIALS=$(printf '%s:%s' "$SIGMA_CLIENT_ID" "$SIGMA_CLIENT_SECRET" | base64)

RESPONSE=$(curl -sf -X POST \
  -H "Authorization: Basic ${CREDENTIALS}" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  "$SIGMA_BASE_URL/v2/auth/token") || {
    echo "Token exchange failed — check SIGMA_BASE_URL, SIGMA_CLIENT_ID, SIGMA_CLIENT_SECRET" >&2
    exit 1
  }

TOKEN=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])" 2>/dev/null \
  || echo "$RESPONSE" | ruby -r json -e "print JSON.parse(STDIN.read)['access_token']")

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "Token exchange failed — response did not contain access_token" >&2
  exit 1
fi

echo "export SIGMA_API_TOKEN=${TOKEN}"
