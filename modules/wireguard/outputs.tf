output "public_ip" {
  description = "Auto-assigned public IP of the VPN server. Changes every time the stack is rebuilt."
  value       = aws_instance.this.public_ip
}

output "instance_id" {
  description = "EC2 instance ID."
  value       = aws_instance.this.id
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

output "idle_shutdown_minutes" {
  description = "Minutes without a client handshake before the instance terminates itself."
  value       = var.idle_shutdown_minutes
}
