output "access_url" {
  value = "http://${aws_lb.my_alb.dns_name}/index.html"
}
