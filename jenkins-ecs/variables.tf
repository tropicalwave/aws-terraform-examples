variable "region" {
  default = "eu-west-1"
  type    = string
}

variable "jenkins_image" {
  default = "jenkins/jenkins:2.479.2-lts-alpine"
  type    = string
}

variable "admin_pw" {
  default = "your_secure_password"
  type    = string
}
