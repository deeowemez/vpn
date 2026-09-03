#!/usr/bin/env bash
# Pulls the WireGuard client configs off the server over SSM Session Manager.
# Waits for the instance to register with SSM and for its bootstrap to finish.
#
# Usage: ./scripts/fetch-clients.sh <region> <instance-id>
set -euo pipefail

REGION="${1:-ap-southeast-2}"
INSTANCE_ID="${2:-}"
OUT_DIR="${OUT_DIR:-clients}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-420}"

command -v aws >/dev/null || { echo "aws CLI not found" >&2; exit 1; }

if [[ -z "$INSTANCE_ID" ]]; then
  INSTANCE_ID="$(terraform output -raw instance_id 2>/dev/null || true)"
fi
if [[ -z "$INSTANCE_ID" ]]; then
  echo "usage: $0 <region> <instance-id>  (or run from a directory with terraform state)" >&2
  exit 1
fi

deadline=$(( $(date +%s) + TIMEOUT_SECONDS ))

# The SSM agent registers a little after the instance boots; nothing can run
# remotely until it does.
printf 'Waiting for %s to register with SSM' "$INSTANCE_ID"
until [[ "$(aws ssm describe-instance-information --region "$REGION" \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null)" == "Online" ]]; do
  if (( $(date +%s) > deadline )); then
    echo $'\nTimed out waiting for the SSM agent. Check the instance in the console.' >&2
    exit 1
  fi
  printf '.'
  sleep 5
done
echo ' online.'

PARAMS_FILE="$(mktemp)"
OUTPUT_FILE="$(mktemp)"
trap 'rm -f "$PARAMS_FILE" "$OUTPUT_FILE"' EXIT

cat > "$PARAMS_FILE" <<'JSON'
{
  "commands": [
    "if [ -f /var/lib/wg-bootstrap.done ]; then tar -C /etc/wireguard/clients -czf - . | base64 -w0; else echo NOT_READY; fi"
  ]
}
JSON

run_remote() {
  local command_id status
  command_id="$(aws ssm send-command \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --document-name AWS-RunShellScript \
    --parameters "file://$PARAMS_FILE" \
    --query 'Command.CommandId' --output text)"

  while :; do
    sleep 3
    status="$(aws ssm get-command-invocation \
      --region "$REGION" --command-id "$command_id" --instance-id "$INSTANCE_ID" \
      --query 'Status' --output text 2>/dev/null || echo Pending)"
    case "$status" in
      Success) break ;;
      Failed|Cancelled|TimedOut) echo "remote command $status" >&2; return 1 ;;
    esac
    (( $(date +%s) > deadline )) && { echo "remote command timed out" >&2; return 1; }
  done

  aws ssm get-command-invocation \
    --region "$REGION" --command-id "$command_id" --instance-id "$INSTANCE_ID" \
    --query 'StandardOutputContent' --output text
}

# First boot installs packages and generates keys; poll until it reports done.
printf 'Waiting for the server bootstrap to finish'
while :; do
  run_remote > "$OUTPUT_FILE" || exit 1
  if [[ "$(head -c 9 "$OUTPUT_FILE")" != "NOT_READY" ]]; then
    break
  fi
  if (( $(date +%s) > deadline )); then
    echo $'\nTimed out. Inspect the log with:' >&2
    echo "  aws ssm start-session --region $REGION --target $INSTANCE_ID" >&2
    echo "  sudo tail -50 /var/log/wg-bootstrap.log" >&2
    exit 1
  fi
  printf '.'
  sleep 10
done
echo ' done.'

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"
# openssl rather than base64, whose decode flag differs between macOS and Linux.
tr -d '\n' < "$OUTPUT_FILE" | openssl base64 -d -A | tar -xzf - -C "$OUT_DIR"
chmod 600 "$OUT_DIR"/*.conf
ls -1 "$OUT_DIR"/*.conf | sed 's/^/wrote /'

echo
echo "Connect on this machine:"
echo "  sudo wg-quick up \$PWD/$OUT_DIR/client1.conf"
echo "  curl https://ifconfig.me     # should be the Sydney address"
echo "  sudo wg-quick down \$PWD/$OUT_DIR/client1.conf"

if command -v qrencode >/dev/null 2>&1 && [[ -f "$OUT_DIR/client2.conf" ]]; then
  echo
  echo "Phone setup - scan with the WireGuard app (client2):"
  qrencode -t ansiutf8 < "$OUT_DIR/client2.conf"
elif ! command -v qrencode >/dev/null 2>&1; then
  echo
  echo "  (brew install qrencode to get a scannable QR code for your phone)"
fi
