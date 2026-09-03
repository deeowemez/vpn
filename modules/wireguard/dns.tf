# Optional stable hostname for the tunnel endpoint. The zone is expected to
# already exist - see scripts/setup-dns.sh - because destroying it with the
# rest of the stack would change its nameservers and break the delegation at
# the registrar every time.
data "aws_route53_zone" "vpn" {
  count        = var.vpn_hostname == null ? 0 : 1
  name         = var.vpn_hostname
  private_zone = false
}

resource "aws_route53_record" "vpn" {
  count   = var.vpn_hostname == null ? 0 : 1
  zone_id = data.aws_route53_zone.vpn[0].zone_id
  name    = var.vpn_hostname
  type    = "A"
  records = [aws_instance.this.public_ip]

  # A new address on every rebuild, so the record must not be cached for long.
  ttl = 60
}
