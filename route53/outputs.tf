output "name_servers" {
  description = "name servers for main domain"
  value       = "${aws_route53_zone.zone[var.main_domain].name_servers}"
}
