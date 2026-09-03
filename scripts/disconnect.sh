#!/usr/bin/env bash
# Takes the tunnel down. Safe to run when it is not up.
# Usage: ./scripts/disconnect.sh [clients/client1.conf]
set -euo pipefail

CONF="${1:-clients/client1.conf}"
[[ -f "$CONF" ]] || { echo "no such config: $CONF" >&2; exit 1; }
CONF_PATH="$(cd "$(dirname "$CONF")" && pwd)/$(basename "$CONF")"

if sudo wg-quick down "$CONF_PATH" 2>/dev/null; then
  echo "Tunnel down."
else
  echo "Tunnel was not up."
fi
