locals {
  # AWS reserves the .2 address of the VPC CIDR for its DNS resolver. Forwarding
  # tunnel DNS there keeps lookups inside the region, so name resolution
  # geolocates the same way the traffic does.
  vpc_resolver_ip = cidrhost(var.vpc_cidr, 2)
  server_wg_ip    = cidrhost(var.wg_subnet_cidr, 1)

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    wg_port               = var.wg_port
    wg_mtu                = var.wg_mtu
    wg_subnet_cidr        = var.wg_subnet_cidr
    server_wg_ip          = local.server_wg_ip
    client_count          = var.client_count
    dns_upstream          = local.vpc_resolver_ip
    idle_shutdown_minutes = var.idle_shutdown_minutes
  })
}

check "ssh_exposure" {
  assert {
    condition     = !var.enable_ssh || (length(var.allowed_ssh_cidrs) > 0 && !contains(var.allowed_ssh_cidrs, "0.0.0.0/0"))
    error_message = "enable_ssh requires allowed_ssh_cidrs to be set and to exclude 0.0.0.0/0. Prefer SSM Session Manager."
  }
}

data "aws_ssm_parameter" "ubuntu" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/${var.ami_architecture}/hvm/ebs-gp3/ami-id"
}

resource "aws_instance" "this" {
  ami           = coalesce(var.ami_id, nonsensitive(data.aws_ssm_parameter.ubuntu.value))
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public.id
  key_name      = var.ssh_key_name

  vpc_security_group_ids = [aws_security_group.this.id]
  iam_instance_profile   = aws_iam_instance_profile.this.name

  # No Elastic IP: a public IPv4 is billed by the hour whether or not the
  # instance is running, and this stack is meant to exist only during a match.
  # An auto-assigned address costs nothing once the instance is gone; the
  # server reads it from instance metadata at boot.
  associate_public_ip_address = true

  # Source/dest checking would drop the client traffic we NAT on the way out.
  source_dest_check = false

  # The in-guest idle timer calls poweroff, so shutdown has to mean terminate
  # for the instance to actually stop costing money. Anything written to the
  # root volume during a session is disposable by design.
  instance_initiated_shutdown_behavior = var.idle_shutdown_minutes > 0 ? "terminate" : "stop"

  user_data                   = local.user_data
  user_data_replace_on_change = true

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size
    encrypted   = true
  }

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  tags = { Name = var.name }
}
