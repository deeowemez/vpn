output "public_ip" {
  description = "Elastic IP of the VPN server."
  value       = aws_eip.this.public_ip
}

output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.this.id
}

output "ssm_parameter_prefix" {
  description = "SSM path under which client configs are published."
  value       = local.ssm_prefix
}

output "security_group_id" {
  description = "Security group protecting the VPN server."
  value       = aws_security_group.this.id
}

output "vpc_id" {
  description = "VPC created for the VPN."
  value       = aws_vpc.this.id
}

output "wg_port" {
  description = "WireGuard UDP port."
  value       = var.wg_port
}
