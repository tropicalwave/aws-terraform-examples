locals {
  mime_types = jsondecode(file("${path.module}/mime.json"))
}

resource "random_pet" "this" {
  length = 4
}

module "s3_bucket" {
  source        = "terraform-aws-modules/s3-bucket/aws"
  bucket        = "static-website-${random_pet.this.id}"
  force_destroy = true
  version       = "~> 3.0"

  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"
}

resource "aws_s3_object" "object" {
  for_each     = fileset("${path.root}/data", "**/*")
  bucket       = module.s3_bucket.s3_bucket_id
  key          = each.value
  source       = "${path.root}/data/${each.value}"
  etag         = filemd5("${path.root}/data/${each.value}")
  content_type = lookup(local.mime_types, regex("\\.[^.]+$", each.value), null)
}

data "aws_iam_policy_document" "s3_policy" {
  version = "2012-10-17"
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${module.s3_bucket.s3_bucket_arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [module.cdn.cloudfront_distribution_arn]

    }
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
  }
}

resource "aws_s3_bucket_policy" "docs" {
  bucket = module.s3_bucket.s3_bucket_id
  policy = data.aws_iam_policy_document.s3_policy.json
}

data "aws_canonical_user_id" "current" {}
data "aws_cloudfront_log_delivery_canonical_user_id" "cloudfront" {}

module "log_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  control_object_ownership = true
  object_ownership         = "BucketOwnerPreferred"

  bucket = "logs-${random_pet.this.id}"
  grant = [{
    type       = "CanonicalUser"
    permission = "FULL_CONTROL"
    id         = data.aws_canonical_user_id.current.id
    }, {
    type       = "CanonicalUser"
    permission = "FULL_CONTROL"
    id         = data.aws_cloudfront_log_delivery_canonical_user_id.cloudfront.id
  }]
  force_destroy = true
}

module "cdn" {
  source              = "terraform-aws-modules/cloudfront/aws"
  version             = "~> 3.0"
  is_ipv6_enabled     = true
  price_class         = "PriceClass_100"
  wait_for_deployment = false

  create_origin_access_control = true
  origin_access_control = {
    s3_oac = {
      "description" : "",
      "origin_type" : "s3",
      "signing_behavior" : "always",
      "signing_protocol" : "sigv4"
    }
  }

  origin = {
    # use origin access control settings (recommended)
    s3_oac = {
      domain_name           = module.s3_bucket.s3_bucket_bucket_regional_domain_name
      origin_access_control = "s3_oac"
    }
  }

  default_cache_behavior = {
    target_origin_id       = "s3_oac"
    viewer_protocol_policy = "redirect-to-https"

    default_ttl = 5400
    min_ttl     = 3600
    max_ttl     = 7200

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]
    compress        = true
    query_string    = false
  }

  default_root_object = "index.html"
}
