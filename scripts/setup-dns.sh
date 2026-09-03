#!/usr/bin/env bash
# One-time setup: creates a Route 53 hosted zone for the VPN subdomain and
# prints the NS records to add at your registrar. Idempotent.
#
# Usage: ./scripts/setup-dns.sh vpn.deeowemez.space
set -euo pipefail

FQDN="${1:?usage: setup-dns.sh <vpn.example.com>}"
FQDN="${FQDN%.}"

command -v aws >/dev/null || { echo "aws CLI not found" >&2; exit 1; }

zone_id="$(aws route53 list-hosted-zones-by-name --dns-name "$FQDN" \
  --query "HostedZones[?Name=='$FQDN.'].Id" --output text 2>/dev/null | head -n1)"

if [[ -z "$zone_id" || "$zone_id" == "None" ]]; then
  echo "Creating hosted zone for $FQDN (\$0.50/month)..."
  zone_id="$(aws route53 create-hosted-zone \
    --name "$FQDN" \
    --caller-reference "vpn-$(date +%s)" \
    --hosted-zone-config "Comment=WireGuard VPN endpoint,PrivateZone=false" \
    --query 'HostedZone.Id' --output text)"
else
  echo "Hosted zone for $FQDN already exists."
fi
zone_id="${zone_id##*/}"
echo "Zone ID: $zone_id"

# Route 53 defaults the SOA negative-caching TTL to 86400. The A record comes
# and goes with each match, so without lowering this a lookup made while the
# VPN is down would cache NXDOMAIN for a day and the next session would fail
# to resolve.
soa="$(aws route53 list-resource-record-sets --hosted-zone-id "$zone_id" \
  --query "ResourceRecordSets[?Type=='SOA'].ResourceRecords[0].Value" --output text)"
new_soa="$(echo "$soa" | awk '{ $NF = 60; print }')"

if [[ "$soa" != "$new_soa" ]]; then
  echo "Lowering SOA negative-cache TTL to 60s..."
  change_batch="$(mktemp)"
  trap 'rm -f "$change_batch"' EXIT
  cat > "$change_batch" <<JSON
{
  "Comment": "Lower negative caching TTL for an ephemeral A record",
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "$FQDN.",
      "Type": "SOA",
      "TTL": 60,
      "ResourceRecords": [{ "Value": "$new_soa" }]
    }
  }]
}
JSON
  aws route53 change-resource-record-sets --hosted-zone-id "$zone_id" \
    --change-batch "file://$change_batch" --query 'ChangeInfo.Status' --output text
fi

echo
echo "=============================================================="
echo " Add these NS records at your registrar, then you are done."
echo "=============================================================="
echo
sub="${FQDN%%.*}"
echo "  Type: NS    Host/Name: $sub    TTL: 3600"
echo "  Points to (one record per line, or one record with four values):"
aws route53 get-hosted-zone --id "$zone_id" \
  --query 'DelegationSet.NameServers' --output text | tr '\t' '\n' | sed 's/^/    /'
echo
echo "Delegation takes a few minutes to propagate. Verify with:"
echo "  dig +short NS $FQDN"
echo
echo "Then set in terraform.tfvars:  vpn_hostname = \"$FQDN\""
