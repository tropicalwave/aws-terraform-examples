variable "main_domain" {
  description = "main domain of deployment (whose name servers will be printed on deployment)"
  default     = "my.test"
  type        = string
}

variable "region" {
  description = "AWS region"
  default     = "eu-west-1"
  type        = string
}
