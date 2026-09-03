variable "name" {
  description = "Name prefix for all resources."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type. Must match the architecture of the resolved AMI (arm64 by default)."
  type        = string
  default     = "t4g.small"
}

variable "ami_id" {
  description = "Override the AMI. Defaults to the latest Ubuntu 24.04 LTS arm64 image."
  type        = string
  default     = null
}

variable "ami_architecture" {
  description = "Architecture of the default Ubuntu AMI to resolve: arm64 or amd64."
  type        = string
  default     = "arm64"

  validation {
    condition     = contains(["arm64", "amd64"], var.ami_architecture)
    error_message = "ami_architecture must be arm64 or amd64."
  }
}

variable "vpc_cidr" {
  description = "CIDR for the VPC created for the VPN."
  type        = string
  default     = "10.20.0.0/16"
}

variable "wg_subnet_cidr" {
  description = "Private CIDR used inside the WireGuard tunnel. Must not overlap vpc_cidr or your home LAN."
  type        = string
  default     = "10.8.0.0/24"
}

variable "wg_port" {
  description = "WireGuard UDP listen port."
  type        = number
  default     = 51820
}

variable "wg_mtu" {
  description = "Tunnel MTU. 1420 is safe over a 1500-byte path; drop to 1380 if you see stalls."
  type        = number
  default     = 1420
}

variable "client_count" {
  description = "Number of client configs to generate at boot."
  type        = number
  default     = 3
}

variable "allowed_vpn_cidrs" {
  description = "Source CIDRs allowed to reach the WireGuard UDP port."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_ssh" {
  description = "Open TCP 22 to allowed_ssh_cidrs."
  type        = bool
  default     = false
}

variable "allowed_ssh_cidrs" {
  description = "Source CIDRs for SSH."
  type        = list(string)
  default     = []
}

variable "ssh_key_name" {
  description = "Existing EC2 key pair name."
  type        = string
  default     = null
}

variable "vpn_hostname" {
  description = <<-EOT
    FQDN to point at the server, e.g. "vpn.example.com". A public Route 53
    hosted zone of exactly this name must already exist; scripts/setup-dns.sh
    creates one and prints the NS records to add at your registrar. When set,
    client configs use this name instead of a bare IP and survive rebuilds.
  EOT
  type        = string
  default     = null
}

variable "server_private_key" {
  description = <<-EOT
    WireGuard server private key. Supplying one (from scripts/gen-keys.sh) lets
    the server keep the same identity across rebuilds, so client configs stay
    valid. Empty means generate a throwaway key at boot.
  EOT
  type        = string
  default     = ""
  sensitive   = true
}

variable "peer_stanzas" {
  description = <<-EOT
    Rendered [Peer] blocks appended verbatim to the server's wg0.conf. Produced
    by scripts/gen-keys.sh as keys/peers.conf. Required when
    server_private_key is set; ignored otherwise.
  EOT
  type        = string
  default     = ""
}

variable "idle_shutdown_minutes" {
  description = <<-EOT
    Terminate the instance after this many minutes with no WireGuard handshake
    from any client. This is the cost guardrail for the ephemeral workflow: an
    instance you forget to destroy cleans itself up. Set to 0 to disable, which
    also changes shutdown behaviour from terminate to stop.
  EOT
  type        = number
  default     = 30
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB."
  type        = number
  default     = 8
}
