terraform {
  required_version = "~> 1.9.0"

  required_providers {
    http = {
      source  = "hashicorp/http"
      version = ">= 2.2.0"
    }

    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.22.0"
    }
  }
}

data "aws_availability_zones" "available" {}

data "http" "myip" {
  url = "https://ipv4.icanhazip.com"
}

module "vpc" {
  #checkov:skip=CKV_TF_1:ensure easier readability for examples
  source          = "terraform-aws-modules/vpc/aws"
  name            = "${var.namespace}-vpc"
  cidr            = "10.0.0.0/16"
  azs             = data.aws_availability_zones.available.names
  public_subnets  = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24", "10.0.5.0/24"]
  version         = ">= 2.0.0"
}

resource "aws_security_group" "allow_ssh_pub" {
  #ts:skip=AC_AWS_0319
  #checkov:skip=CKV2_AWS_5:associated dynamically to autoscaling group
  name        = "${var.namespace}-allow_ssh"
  description = "Allow SSH inbound traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.myip.response_body)}/32"]
  }

  egress {
    description = "allow all outgoing traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "allow_efs" {
  #checkov:skip=CKV2_AWS_5:associated dynamically to autoscaling group
  name        = "${var.namespace}-allow_efs"
  description = "Allow EFS traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "EFS"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.allow_ssh_pub.id]
  }
}

resource "aws_eip" "one" {
  #checkov:skip=CKV2_AWS_19:EIP is associated dynamically
  domain = "vpc"
}
