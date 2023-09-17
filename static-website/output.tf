output "cloudfront_distribution_domain_name" {
  value = "https://${module.cdn.cloudfront_distribution_domain_name}"
}
