provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project = "alb-private-api"
    }
  }
}
