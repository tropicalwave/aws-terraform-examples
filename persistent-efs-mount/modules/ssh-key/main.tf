// Generate SSH keypair and upload the public key to AWS
terraform {
  required_version = "~> 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.22.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = ">= 3.4.0"
    }

    local = {
      source  = "hashicorp/local"
      version = ">= 2.2.3"
    }
  }
}

resource "tls_private_key" "key" {
  algorithm = "RSA"
}

resource "local_sensitive_file" "private_key" {
  filename        = "${var.namespace}-key.pem"
  content         = tls_private_key.key.private_key_pem
  file_permission = "0400"
}

resource "aws_key_pair" "key_pair" {
  key_name   = "${var.namespace}-key"
  public_key = tls_private_key.key.public_key_openssh
}
