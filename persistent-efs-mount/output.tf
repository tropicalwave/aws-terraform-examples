output "connection_string" {
  description = "Login to EC2 instance"
  value       = "ssh -i ${module.ssh-key.key_name}.pem ec2-user@${module.networking.one_eip.public_ip}"
}
