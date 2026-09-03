locals {
  ssm_prefix = "/${var.name}/wireguard"

  # AWS reserves the .2 address of the VPC CIDR for its DNS resolver. Forwarding
  # tunnel DNS there keeps lookups inside the region, so name resolution
  # geolocates the same way the traffic does.
  vpc_resolver_ip = cidrhost(var.vpc_cidr, 2)
  server_wg_ip    = cidrhost(var.wg_subnet_cidr, 1)

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    region          = var.region
    ssm_prefix      = local.ssm_prefix
    wg_port         = var.wg_port
    wg_mtu          = var.wg_mtu
    wg_subnet_cidr  = var.wg_subnet_cidr
    server_wg_ip    = local.server_wg_ip
    client_count    = var.client_count
    dns_upstream    = local.vpc_resolver_ip
    public_endpoint = aws_eip.this.public_ip
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

# Allocated before the instance so its address can be baked into the client
# configs that user_data writes on first boot.
resource "aws_eip" "this" {
  domain = "vpc"

  tags = { Name = var.name }
}

resource "aws_instance" "this" {
  ami           = coalesce(var.ami_id, nonsensitive(data.aws_ssm_parameter.ubuntu.value))
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public.id
  key_name      = var.ssh_key_name

  vpc_security_group_ids = [aws_security_group.this.id]
  iam_instance_profile   = aws_iam_instance_profile.this.name

  # Source/dest checking would drop the client traffic we NAT on the way out.
  source_dest_check = false

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

resource "aws_eip_association" "this" {
  allocation_id = aws_eip.this.id
  instance_id   = aws_instance.this.id
}
