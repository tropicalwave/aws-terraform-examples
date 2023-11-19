output "vpc" {
  value = module.vpc
}

output "sg_efs_id" {
  value = aws_security_group.allow_efs.id
}

output "sg_ssh_id" {
  value = aws_security_group.allow_ssh_pub.id
}
