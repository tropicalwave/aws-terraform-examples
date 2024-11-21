output "access_url" {
  value = "http://${aws_lb.jenkins.dns_name}"
}
