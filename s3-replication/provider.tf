terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.77.0"
    }
  }
}

provider "aws" {
  alias  = "source"
  region = "eu-west-1"

  default_tags {
    tags = {
      Project = "s3-replication"
    }
  }
}

provider "aws" {
  alias  = "destination"
  region = "eu-central-1"

  default_tags {
    tags = {
      Project = "s3-replication"
    }
  }
}

