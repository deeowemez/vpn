#!/usr/bin/env bash
# Points a Hostinger-hosted DNS record at the current VPN server.
#
# Hostinger's DNS editor cannot create NS records, so the VPN subdomain cannot
# be delegated to Route 53. Instead we update the A record in place through
# Hostinger's own API, which keeps DNS where it already is and costs nothing.
#
#   ./scripts/hostinger-dns.sh get   vpn.example.com
#   ./scripts/hostinger-dns.sh set   vpn.example.com 13.55.1.2
#   ./scripts/hostinger-dns.sh clear vpn.example.com
#
# Requires HOSTINGER_API_TOKEN (hPanel -> Account -> API). A .env file in the
# repo root is sourced if present. Pass --dry-run to print the request only.
set -euo pipefail

API_BASE="${HOSTINGER_API_BASE:-https://developers.hostinger.com}"
TTL="${TTL:-60}"
DRY_RUN=0

# RFC 5737 documentation address. Parking the record here rather than deleting
# it means no NXDOMAIN gets negatively cached while the VPN is torn down, and
# the name never dangles at a recycled AWS address someone else now owns.
BLACKHOLE_IP="192.0.2.1"

[[ -f .env ]] && . ./.env

args=()
for a in "$@"; do
  case "$a" in
    --dry-run) DRY_RUN=1 ;;
    *) args+=("$a") ;;
  esac
done
set -- ${args[@]+"${args[@]}"}

ACTION="${1:-}"
FQDN="${2:-}"
[[ -n "$ACTION" && -n "$FQDN" ]] || {
  echo "usage: $0 {get|set|clear} <fqdn> [ip] [--dry-run]" >&2; exit 1; }
FQDN="${FQDN%.}"

# vpn.example.com -> domain example.com, record name "vpn". Override
# HOSTINGER_DOMAIN for multi-label suffixes such as .co.uk.
DOMAIN="${HOSTINGER_DOMAIN:-$(echo "$FQDN" | rev | cut -d. -f1-2 | rev)}"
RECORD_NAME="${FQDN%".$DOMAIN"}"
[[ "$RECORD_NAME" == "$FQDN" ]] && RECORD_NAME="@"

if [[ -z "${HOSTINGER_API_TOKEN:-}" && "$DRY_RUN" -eq 0 ]]; then
  echo "HOSTINGER_API_TOKEN is not set." >&2
  echo "Create one at hPanel -> Account -> API, then either export it or put" >&2
  echo "  HOSTINGER_API_TOKEN=xxxxx" >&2
  echo "in a .env file in the repo root (already gitignored)." >&2
  exit 1
fi

api() {
  local method="$1" path="$2" body="${3:-}"
  local -a curl_args=(
    -sS --fail-with-body -X "$method"
    -H "Authorization: Bearer ${HOSTINGER_API_TOKEN:-DRY_RUN}"
    -H "Content-Type: application/json"
    -H "Accept: application/json"
  )
  [[ -n "$body" ]] && curl_args+=(-d "$body")

  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "DRY RUN: $method $API_BASE$path"
    [[ -n "$body" ]] && echo "$body"
    return 0
  fi
  curl "${curl_args[@]}" "$API_BASE$path"
}

# Buffer first: piping straight into json.tool consumes stdin, so a non-JSON
# response would fall through to an empty cat.
pretty() {
  local out
  out="$(cat)"
  echo "$out" | python3 -m json.tool 2>/dev/null || echo "$out"
}

put_a_record() {
  local ip="$1"
  # overwrite=false so only this record set is touched; everything else in the
  # zone (the apex A, the www CNAME) is left alone.
  local body
  body=$(cat <<JSON
{
  "overwrite": false,
  "zone": [
    {
      "name": "$RECORD_NAME",
      "type": "A",
      "ttl": $TTL,
      "records": [ { "content": "$ip" } ]
    }
  ]
}
JSON
)
  api PUT "/api/dns/v1/zones/$DOMAIN" "$body" | pretty
}

case "$ACTION" in
  get)
    api GET "/api/dns/v1/zones/$DOMAIN" | pretty
    ;;
  set)
    IP="${3:-}"
    [[ -n "$IP" ]] || { echo "usage: $0 set <fqdn> <ip>" >&2; exit 1; }
    echo "Pointing $FQDN at $IP (TTL ${TTL}s)..."
    put_a_record "$IP"
    echo "Done. Verify with: dig +short $FQDN"
    ;;
  clear)
    echo "Parking $FQDN at $BLACKHOLE_IP..."
    put_a_record "$BLACKHOLE_IP"
    ;;
  *)
    echo "unknown action: $ACTION" >&2; exit 1
    ;;
esac
