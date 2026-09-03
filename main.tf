locals {
  keys_dir = "${path.root}/keys"

  # Supplying a keyset is what makes client configs permanent: the server keeps
  # the same identity across rebuilds. try() rather than fileexists() so a repo
  # without keys/ still plans - that path generates throwaway keys at boot.
  server_private_key = trimspace(try(file("${local.keys_dir}/server.key"), ""))
  peer_stanzas       = try(file("${local.keys_dir}/peers.conf"), "")
}

module "vpn" {
  source = "./modules/wireguard"

  name                  = var.name
  instance_type         = var.instance_type
  ami_architecture      = var.ami_architecture
  client_count          = var.client_count
  wg_port               = var.wg_port
  idle_shutdown_minutes = var.idle_shutdown_minutes
  vpn_hostname          = var.vpn_hostname
  server_private_key    = local.server_private_key
  peer_stanzas          = local.peer_stanzas
  wg_mtu                = var.wg_mtu
  vpc_cidr              = var.vpc_cidr
  wg_subnet_cidr        = var.wg_subnet_cidr
  allowed_vpn_cidrs     = var.allowed_vpn_cidrs
  enable_ssh            = var.enable_ssh
  allowed_ssh_cidrs     = var.allowed_ssh_cidrs
  ssh_key_name          = var.ssh_key_name
}
