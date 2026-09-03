#!/usr/bin/env bash
# Downloads the WireGuard client configs that the server published to SSM
# Parameter Store. Usage: ./scripts/fetch-clients.sh [region] [ssm-prefix]
set -euo pipefail

REGION="${1:-ap-southeast-2}"
PREFIX="${2:-/vpn-syd/wireguard}"
OUT_DIR="${OUT_DIR:-clients}"

command -v aws >/dev/null || { echo "aws CLI not found" >&2; exit 1; }

status="$(aws ssm get-parameter --region "$REGION" --name "$PREFIX/status" \
  --query 'Parameter.Value' --output text 2>/dev/null || true)"

if [[ -z "$status" ]]; then
  echo "Server has not finished bootstrapping yet (no $PREFIX/status parameter)."
  echo "First boot installs packages and takes ~90-150s. Retry shortly, or watch:"
  echo "  aws ssm start-session --region $REGION --target <instance-id>"
  echo "  sudo tail -f /var/log/wg-bootstrap.log"
  exit 1
fi
echo "Server status: $status"

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

# Read into an array without mapfile, which macOS's bash 3.2 lacks.
names=()
while IFS= read -r line; do
  [[ -n "$line" ]] && names+=("$line")
done < <(
  aws ssm get-parameters-by-path \
    --region "$REGION" \
    --path "$PREFIX/clients" \
    --with-decryption \
    --query 'Parameters[].Name' \
    --output text | tr '\t' '\n'
)

if [[ -z "${names[*]:-}" ]]; then
  echo "No client configs found under $PREFIX/clients" >&2
  exit 1
fi

for name in "${names[@]}"; do
  base="$(basename "$name")"
  dest="$OUT_DIR/$base.conf"
  aws ssm get-parameter --region "$REGION" --name "$name" --with-decryption \
    --query 'Parameter.Value' --output text > "$dest"
  chmod 600 "$dest"
  echo "wrote $dest"
done

echo
echo "Import a config into the WireGuard app, or on Linux/macOS:"
echo "  sudo wg-quick up \$PWD/$OUT_DIR/client1.conf"
if command -v qrencode >/dev/null 2>&1; then
  echo
  echo "Phone setup - scan this with the WireGuard app (client1):"
  qrencode -t ansiutf8 < "$OUT_DIR/client1.conf"
else
  echo "  (install qrencode to print a QR code for phone setup)"
fi
