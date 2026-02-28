#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "[ERROR] .env not found. Run: cp .env.example .env"
  exit 1
fi

# export env vars for current shell
set -a
source "$ENV_FILE"
set +a

# install into ~/.openclaw/scripts
TARGET_DIR="$HOME/.openclaw/scripts"
mkdir -p "$TARGET_DIR"

cp -f "$ROOT_DIR"/*.sh "$TARGET_DIR/"
cp -f "$ROOT_DIR"/README.md "$TARGET_DIR/" 2>/dev/null || true
cp -f "$ROOT_DIR"/README-proxy-health.md "$TARGET_DIR/" 2>/dev/null || true

chmod +x "$TARGET_DIR"/*.sh

OS="$(uname -s)"

if [[ "$OS" == "Darwin" ]]; then
  echo "[INFO] macOS detected. Use LaunchAgent (plist not provided)."
  echo "  - Place plist in ~/Library/LaunchAgents"
  echo "  - launchctl load ~/Library/LaunchAgents/ai.openclaw.watchdog.plist"
  echo "  - launchctl load ~/Library/LaunchAgents/ai.openclaw.proxy-health.plist"
elif [[ "$OS" == "Linux" ]]; then
  echo "[INFO] Linux detected. systemd unit examples:" 
  echo "  /etc/systemd/system/openclaw-watchdog.service"
  echo "  /etc/systemd/system/openclaw-proxy-health.service"
else
  echo "[WARN] Unknown OS: $OS. Install manually."
fi

echo "[OK] Scripts installed to $TARGET_DIR"
