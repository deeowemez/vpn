#!/usr/bin/env bash
# One-time setup: generates a permanent WireGuard keyset and the client configs
# that go with it. Terraform feeds keys/server.key and keys/peers.conf to the
# server on every rebuild, so the configs in clients/ keep working forever.
#
# Usage: ./scripts/gen-keys.sh --host vpn.example.com [--count 3] [--port 51820]
set -euo pipefail

HOST=""
COUNT=3
PORT=51820
MTU=1420
SUBNET_PREFIX="10.8.0"
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)   HOST="$2"; shift 2 ;;
    --count)  COUNT="$2"; shift 2 ;;
    --port)   PORT="$2"; shift 2 ;;
    --mtu)    MTU="$2"; shift 2 ;;
    --subnet-prefix) SUBNET_PREFIX="$2"; shift 2 ;;
    --force)  FORCE=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$HOST" ]] || { echo "usage: $0 --host vpn.example.com [--count N]" >&2; exit 1; }

if ! command -v wg >/dev/null 2>&1; then
  echo "The 'wg' command is required to generate keys." >&2
  echo "  macOS:  brew install wireguard-tools" >&2
  echo "  Debian: sudo apt install wireguard-tools" >&2
  exit 1
fi

if [[ -f keys/server.key && "$FORCE" -ne 1 ]]; then
  echo "keys/ already exists. Regenerating invalidates every config you have" >&2
  echo "already installed on your devices. Pass --force if that is what you want." >&2
  exit 1
fi

umask 077
mkdir -p keys clients
chmod 700 keys clients

wg genkey > keys/server.key
wg pubkey < keys/server.key > keys/server.pub
SERVER_PUB="$(cat keys/server.pub)"
SERVER_IP="$SUBNET_PREFIX.1"

# peers.conf is consumed verbatim by Terraform and appended to the server's
# wg0.conf, so nothing has to parse it on either side.
: > keys/peers.conf

for i in $(seq 1 "$COUNT"); do
  name="client$i"
  addr="$SUBNET_PREFIX.$((i + 1))"

  wg genkey > "keys/$name.key"
  wg pubkey < "keys/$name.key" > "keys/$name.pub"

  cat >> keys/peers.conf <<PEER

[Peer]
# $name
PublicKey = $(cat "keys/$name.pub")
AllowedIPs = $addr/32
PEER

  cat > "clients/$name.conf" <<CLIENT
[Interface]
PrivateKey = $(cat "keys/$name.key")
Address = $addr/32
DNS = $SERVER_IP
MTU = $MTU

[Peer]
PublicKey = $SERVER_PUB
Endpoint = $HOST:$PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
CLIENT

  chmod 600 "clients/$name.conf"
  echo "generated $name ($addr)"
done

echo
echo "Configs in clients/ are permanent - install them once, on every device."
echo "  macOS/Linux: sudo wg-quick up \$PWD/clients/client1.conf"

if command -v qrencode >/dev/null 2>&1; then
  echo
  echo "Phone setup - scan with the WireGuard app (client2):"
  qrencode -t ansiutf8 < clients/client2.conf 2>/dev/null || true
else
  echo "  (brew install qrencode for a scannable QR code)"
fi
