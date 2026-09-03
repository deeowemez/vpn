module "vpn" {
  source = "./modules/wireguard"

  name              = var.name
  region            = var.region
  instance_type     = var.instance_type
  ami_architecture  = var.ami_architecture
  client_count      = var.client_count
  wg_port           = var.wg_port
  wg_mtu            = var.wg_mtu
  vpc_cidr          = var.vpc_cidr
  wg_subnet_cidr    = var.wg_subnet_cidr
  allowed_vpn_cidrs = var.allowed_vpn_cidrs
  enable_ssh        = var.enable_ssh
  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  ssh_key_name      = var.ssh_key_name
}
