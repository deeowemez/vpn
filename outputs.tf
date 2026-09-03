output "public_ip" {
  description = "Public IP of the VPN server for this session. A new one is assigned on every rebuild."
  value       = module.vpn.public_ip
}

output "instance_id" {
  description = "EC2 instance ID."
  value       = module.vpn.instance_id
}

output "fetch_clients_command" {
  description = "Pull the generated client configs off the instance over SSM."
  value       = "./scripts/fetch-clients.sh ${var.region} ${module.vpn.instance_id}"
}

output "session_manager_command" {
  description = "Shell onto the box without SSH."
  value       = "aws ssm start-session --region ${var.region} --target ${module.vpn.instance_id}"
}

output "idle_shutdown_note" {
  description = "When the instance will terminate itself if unused."
  value = (
    var.idle_shutdown_minutes > 0
    ? "Self-terminates after ${var.idle_shutdown_minutes} min with no client handshake. Run 'make down' afterwards to clear Terraform state."
    : "Idle shutdown is DISABLED - this instance will run until you stop it."
  )
}
