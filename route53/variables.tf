variable "main_domain" {
  description = "main domain of deployment (whose name servers will be printed on deployment)"
  default     = "my.test"
  type        = string
}

variable "region" {
  description = "AWS region"
  # DNSSEC CMK must be located in us-east-1, see
  # https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/dns-configuring-dnssec-cmk-requirements.html
  default = "us-east-1"
  type    = string
}
