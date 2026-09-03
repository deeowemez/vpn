#!/usr/bin/env bash
# Brings the tunnel up, but only once there is something on the other end - and
# rolls back automatically if traffic does not flow.
#
# A full-tunnel config routes every packet into wg0, so connecting to a server
# that is not running takes the whole machine offline until you notice.
#
# Usage: ./scripts/connect.sh [clients/client1.conf]
set -euo pipefail

CONF="${1:-clients/client1.conf}"
BLACKHOLE_IP="192.0.2.1"

[[ -f "$CONF" ]] || { echo "no such config: $CONF" >&2; exit 1; }
CONF_PATH="$(cd "$(dirname "$CONF")" && pwd)/$(basename "$CONF")"

host="$(sed -n 's/^ *Endpoint *= *\(.*\):[0-9]*$/\1/p' "$CONF_PATH" | head -n1)"
[[ -n "$host" ]] || { echo "could not find an Endpoint in $CONF" >&2; exit 1; }

if [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  ip="$host"
else
  ip="$(dig +short A "$host" | grep -E '^[0-9.]+$' | tail -n1)"
fi

if [[ -z "$ip" ]]; then
  echo "$host does not resolve. Is the DNS record there?" >&2
  exit 1
fi

if [[ "$ip" == "$BLACKHOLE_IP" ]]; then
  echo "$host still points at the $BLACKHOLE_IP placeholder - no server to connect to." >&2
  echo >&2
  echo "  make match          # build the server, prints its address" >&2
  echo "  # paste that address into the 'vpn' A record, wait out the TTL" >&2
  echo "  dig +short $host    # confirm it changed, then run this again" >&2
  exit 1
fi

echo "$host resolves to $ip. Bringing the tunnel up..."
sudo wg-quick up "$CONF_PATH"

# Verify before trusting it. If the server is unreachable the machine is now
# offline, so tear the tunnel back down rather than leaving it that way.
echo -n "Checking that traffic flows... "
if exit_ip="$(curl -fsS --max-time 12 https://api.ipify.org 2>/dev/null)"; then
  echo "ok."
  echo "You are exiting via $exit_ip."
  if [[ "$exit_ip" != "$ip" ]]; then
    echo "Note: that differs from the tunnel endpoint ($ip). Usually harmless."
  fi
  echo
  echo "Disconnect with: ./scripts/disconnect.sh $CONF"
else
  echo "FAILED."
  sudo wg-quick down "$CONF_PATH"
  echo "Tunnel rolled back; your connection is restored." >&2
  echo "The server is up in AWS but not passing traffic. Check the security" >&2
  echo "group port, and the boot log with: make shell" >&2
  exit 1
fi
