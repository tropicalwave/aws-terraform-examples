resource "random_pet" "this" {
  length = 2
}

module "s3_source_bucket" {
  #checkov:skip=CKV_TF_1:ensure easier readability for examples
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket                   = "source-bucket-${random_pet.this.id}"
  acl                      = "private"
  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"
  versioning = {
    enabled = true
  }
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  replication_configuration = {
    role = aws_iam_role.replication.arn

    rules = [
      {
        id       = "replication-rule"
        status   = "Enabled"
        priority = 1

        filter = {
          prefix = ""
        }

        destination = {
          bucket        = module.s3_destination_bucket.s3_bucket_arn
          storage_class = "STANDARD"
        }
      }
    ]
  }

  providers = {
    aws = aws.source
  }
}

module "s3_destination_bucket" {
  #checkov:skip=CKV_TF_1:ensure easier readability for examples
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket                   = "destination-bucket-${random_pet.this.id}"
  acl                      = "private"
  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"
  versioning = {
    enabled = true
  }
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  providers = {
    aws = aws.destination
  }
}

resource "aws_iam_role" "replication" {
  provider = aws.source
  name     = "s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Effect = "Allow"
        Sid    = ""
      }
    ]
  })
}

# see https://docs.aws.amazon.com/AmazonS3/latest/userguide/setting-repl-config-perm-overview.html
resource "aws_iam_policy" "replication" {
  provider = aws.source
  name     = "s3-replication-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket",
        ]
        Effect = "Allow"
        Resource = [
          module.s3_source_bucket.s3_bucket_arn,
        ]
      },
      {
         Action = [
            "s3:GetObjectVersionForReplication",
            "s3:GetObjectVersionAcl",
            "s3:GetObjectVersionTagging",
         ]
         Effect = "Allow"
         Resource = [
          "${module.s3_source_bucket.s3_bucket_arn}/*",
         ]
      },
      {
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags",
        ]
        Effect = "Allow"
        Resource = [
          "${module.s3_destination_bucket.s3_bucket_arn}/*",
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "replication" {
  provider   = aws.source
  role       = aws_iam_role.replication.name
  policy_arn = aws_iam_policy.replication.arn
}
