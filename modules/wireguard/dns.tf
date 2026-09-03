locals {
  # Terraform only manages the record when a Route 53 zone is named. Setting
  # vpn_hostname alone just bakes the name into the client configs, leaving the
  # record to whatever hosts your DNS - see scripts/hostinger-dns.sh for a
  # registrar whose editor cannot create the NS records delegation would need.
  manage_route53 = var.route53_zone_name != null && var.vpn_hostname != null
}

# The zone is expected to already exist: destroying it with the rest of the
# stack would change its nameservers and break delegation at the registrar
# every time.
data "aws_route53_zone" "vpn" {
  count        = local.manage_route53 ? 1 : 0
  name         = var.route53_zone_name
  private_zone = false
}

resource "aws_route53_record" "vpn" {
  count   = local.manage_route53 ? 1 : 0
  zone_id = data.aws_route53_zone.vpn[0].zone_id
  name    = var.vpn_hostname
  type    = "A"
  records = [aws_instance.this.public_ip]

  # A new address on every rebuild, so the record must not be cached for long.
  ttl = 60
}
