variable "region" {
  description = "AWS region to deploy the VPN into. Sydney is ap-southeast-2."
  type        = string
  default     = "ap-southeast-2"
}

variable "name" {
  description = "Name prefix for all resources. Also namespaces the SSM parameters holding client configs."
  type        = string
  default     = "vpn-syd"
}

variable "instance_type" {
  description = <<-EOT
    EC2 instance type. Network throughput matters more than CPU for a VPN.
    t4g.small (ARM) is the cost/throughput sweet spot for 1-3 concurrent
    streams. Step up to t4g.medium or c6gn.medium if you saturate it.
  EOT
  type        = string
  default     = "t4g.small"
}

variable "ami_architecture" {
  description = <<-EOT
    Architecture of the Ubuntu 24.04 AMI to resolve: arm64 or amd64. Must match
    instance_type - t4g/c6g/m7g are arm64, t3/m5/c5 are amd64.
  EOT
  type        = string
  default     = "arm64"
}

variable "client_count" {
  description = "Number of WireGuard client configs to generate at boot."
  type        = number
  default     = 3

  validation {
    condition     = var.client_count >= 1 && var.client_count <= 50
    error_message = "client_count must be between 1 and 50."
  }
}

variable "vpn_hostname" {
  description = <<-EOT
    Stable hostname clients dial, e.g. "vpn.example.com". Generate configs
    against it with scripts/gen-keys.sh and they survive every rebuild. The
    record itself is repointed after each build - by Terraform if
    route53_zone_name is set, otherwise by scripts/hostinger-dns.sh. Leave null
    to dial the raw IP, which changes every time.
  EOT
  type        = string
  default     = null
}

variable "route53_zone_name" {
  description = <<-EOT
    Existing public Route 53 hosted zone holding vpn_hostname. Set this only if
    your DNS is on Route 53; leave null when the registrar hosts it.
  EOT
  type        = string
  default     = null
}

variable "idle_shutdown_minutes" {
  description = <<-EOT
    Terminate the instance after this many minutes with no client handshake.
    This is the cost guardrail: a stack you forget to destroy after a match
    cleans itself up. Note that a device left connected keeps sending
    keepalives, so switch the VPN off when you are done. 0 disables it.
  EOT
  type        = number
  default     = 30
}

variable "allowed_vpn_cidrs" {
  description = <<-EOT
    Source CIDRs allowed to reach the WireGuard UDP port. WireGuard silently
    drops unauthenticated packets, so 0.0.0.0/0 is acceptable; narrow it to
    your ISP prefix if you have a stable one.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "wg_port" {
  description = "WireGuard UDP listen port. 443 or 53 can help on restrictive networks."
  type        = number
  default     = 51820
}

variable "enable_ssh" {
  description = "Open SSH to allowed_ssh_cidrs. Off by default: use SSM Session Manager instead."
  type        = bool
  default     = false
}

variable "allowed_ssh_cidrs" {
  description = "Source CIDRs for SSH when enable_ssh is true. Never leave this as 0.0.0.0/0."
  type        = list(string)
  default     = []
}

variable "ssh_key_name" {
  description = "Existing EC2 key pair name for SSH. Optional."
  type        = string
  default     = null
}

variable "vpc_cidr" {
  description = "CIDR for the VPC created for the VPN."
  type        = string
  default     = "10.20.0.0/16"
}

variable "wg_subnet_cidr" {
  description = "Private CIDR inside the tunnel. Must not overlap vpc_cidr or your home LAN."
  type        = string
  default     = "10.8.0.0/24"
}

variable "wg_mtu" {
  description = "Tunnel MTU. Drop to 1380 if handshakes succeed but traffic stalls."
  type        = number
  default     = 1420
}

variable "tags" {
  description = "Extra tags applied to every resource."
  type        = map(string)
  default     = {}
}
