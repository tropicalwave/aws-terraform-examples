variable "namespace" {
  type = string
}

variable "vpc" {
  type = any
}

variable "key_name" {
  type = string
}

variable "sg_efs_id" {
  type = any
}

variable "sg_ssh_id" {
  type = any
}
