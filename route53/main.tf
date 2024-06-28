locals {
  records_raw = csvdecode(file("${path.module}/records.csv"))
  zones       = toset(distinct(local.records_raw[*].Zone))

  record_groups = tomap({
    for row in local.records_raw :
    "${row.Name} ${row.Zone} ${row.Type}" => row...
  })
  recordsets = tomap({
    for group_key, group in local.record_groups : group_key => {
      name   = group[0].Name
      type   = group[0].Type
      zone   = group[0].Zone
      values = group[*].Value
    }
  })
}

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "example" {
  #ts:skip=AC_AWS_0160
  # automatic key rotation cannot be enabled on asymmetric KMS keys, see
  # https://docs.aws.amazon.com/kms/latest/developerguide/rotate-keys.html
  customer_master_key_spec = "ECC_NIST_P256"
  deletion_window_in_days  = 7
  key_usage                = "SIGN_VERIFY"
  policy = jsonencode({
    Statement = [
      {
        Action = [
          "kms:DescribeKey",
          "kms:GetPublicKey",
          "kms:Sign",
        ],
        Effect = "Allow"
        Principal = {
          Service = "dnssec-route53.amazonaws.com"
        }
        Sid      = "Allow Route 53 DNSSEC Service",
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = "arn:aws:route53:::hostedzone/*"
          }
        }
      },
      {
        Action = "kms:CreateGrant",
        Effect = "Allow"
        Principal = {
          Service = "dnssec-route53.amazonaws.com"
        }
        Sid      = "Allow Route 53 DNSSEC Service to CreateGrant",
        Resource = "*"
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = "true"
          }
        }
      },
      {
        Action = "kms:*"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Resource = "*"
        Sid      = "Enable IAM User Permissions"
      },
    ]
    Version = "2012-10-17"
  })
}

resource "aws_route53_zone" "zone" {
  #checkov:skip=CKV2_AWS_39:disable query logging for tests
  for_each = local.zones
  name     = each.value
}

resource "aws_route53_key_signing_key" "example" {
  for_each                   = local.zones
  hosted_zone_id             = aws_route53_zone.zone[each.value].id
  key_management_service_arn = aws_kms_key.example.arn
  name                       = "example"
}

resource "aws_route53_hosted_zone_dnssec" "example" {
  for_each       = local.zones
  hosted_zone_id = aws_route53_zone.zone[each.value].id
  depends_on = [
    aws_route53_key_signing_key.example
  ]
}

resource "aws_route53_record" "records" {
  for_each = local.recordsets

  name    = "${each.value.name}${each.value.name == "" ? "" : "."}${each.value.zone}"
  type    = each.value.type
  zone_id = aws_route53_zone.zone[each.value.zone].zone_id
  ttl     = 3600
  records = each.value.values
}
