variable "namespace" {
  description = "The project namespace to use for unique resource naming"
  default     = "persistent-efs-mount"
  type        = string
}

variable "region" {
  description = "AWS region"
  default     = "eu-west-1"
  type        = string
}
