output "public_ip" {
  description = "Static (Elastic) IP of the VPN server. This is the Endpoint in your client config."
  value       = module.vpn.public_ip
}

output "instance_id" {
  description = "EC2 instance ID. Use with: aws ssm start-session --target <id>"
  value       = module.vpn.instance_id
}

output "ssm_parameter_prefix" {
  description = "SSM Parameter Store path holding the generated client configs."
  value       = module.vpn.ssm_parameter_prefix
}

output "fetch_clients_command" {
  description = "Run this once the instance finishes booting (~90s) to download client configs."
  value       = "./scripts/fetch-clients.sh ${var.region} ${module.vpn.ssm_parameter_prefix}"
}

output "session_manager_command" {
  description = "Shell onto the box without SSH."
  value       = "aws ssm start-session --region ${var.region} --target ${module.vpn.instance_id}"
}
