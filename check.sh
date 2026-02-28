#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT_DIR/.env"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
fi

missing=0

check_bin() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[MISSING] $1"
    missing=1
  else
    echo "[OK] $1"
  fi
}

check_bin openclaw
check_bin curl
check_bin jq

if [[ -n "${OPENCLAW_HEALTH_URL:-}" ]]; then
  if curl -s -m 5 "$OPENCLAW_HEALTH_URL" >/dev/null 2>&1; then
    echo "[OK] Gateway health reachable"
  else
    echo "[WARN] Gateway health not reachable: $OPENCLAW_HEALTH_URL"
  fi
fi

if [[ -n "${CLASH_API:-}" ]]; then
  if curl -s -m 5 "$CLASH_API/proxies" >/dev/null 2>&1; then
    echo "[OK] Clash API reachable"
  else
    echo "[WARN] Clash API not reachable: $CLASH_API"
  fi
fi

if [[ $missing -eq 1 ]]; then
  echo "[FAIL] Missing requirements"
  exit 1
fi

echo "[DONE] basic checks complete"
