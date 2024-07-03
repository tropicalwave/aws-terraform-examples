data "aws_caller_identity" "current" {}

resource "random_pet" "this" {
  length = 2
}

module "s3_bucket" {
  #checkov:skip=CKV_TF_1:ensure easier readability for examples
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 3.0"

  bucket_prefix = "${random_pet.this.id}-"
  force_destroy = true

  # S3 bucket-level Public Access Block configuration
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

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
}

resource "aws_kms_key" "parameter_key" {
  description             = "KMS key for encrypting SSM parameters"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow key usage by Lambda"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda_role.arn
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_ssm_parameter" "my_parameter" {
  name        = "/my/parameter"
  description = "Parameter protected by custom KMS key"
  type        = "SecureString"
  value       = "0"
  key_id      = aws_kms_key.parameter_key.arn
}

# IAM role for Lambda function
resource "aws_iam_role" "lambda_role" {
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Policies attached to IAM role
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

resource "aws_iam_policy" "ssm_parameter_policy" {
  name        = "ssm_parameter_access_policy"
  path        = "/"
  description = "IAM policy for accessing specific Parameter Store parameter"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:PutParameter"
        ]
        Resource = aws_ssm_parameter.my_parameter.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = aws_kms_key.parameter_key.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_parameter_access" {
  policy_arn = aws_iam_policy.ssm_parameter_policy.arn
  role       = aws_iam_role.lambda_role.name
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "parameter_store_lambda" {
  #checkov:skip=CKV_AWS_116:dead letter queue not of interest in this example
  #checkov:skip=CKV_AWS_173:environment variables are not encrypted with own key
  #checkov:skip=CKV_AWS_117:run lambda function in Lambda VPC
  #checkov:skip=CKV_AWS_50:disable tracing
  #ts:skip=AC_AWS_0486 - no VPC configuration in this example
  #ts:skip=AC_AWS_0483 - environment variables are not encrypted with own key
  #ts:skip=AC_AWS_0485 - disable tracing
  s3_bucket     = module.s3_bucket.s3_bucket_id
  s3_key        = aws_signer_signing_job.this.signed_object[0]["s3"][0]["key"]
  function_name = "parameter_store_lambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.handler"
  runtime       = "python3.12"

  # disable concurrent execution
  reserved_concurrent_executions = 1

  environment {
    variables = {
      PARAMETER_NAME = aws_ssm_parameter.my_parameter.name
    }
  }

  code_signing_config_arn = aws_lambda_code_signing_config.this.arn
}

resource "aws_signer_signing_profile" "this" {
  platform_id = "AWSLambda-SHA384-ECDSA"

  signature_validity_period {
    value = 5
    type  = "YEARS"
  }
}

resource "aws_s3_object" "unsigned" {
  bucket = module.s3_bucket.s3_bucket_id
  key    = "unsigned/existing_package.zip"
  source = data.archive_file.lambda_zip.output_path

  # Making sure that S3 versioning configuration is propagated properly
  depends_on = [
    module.s3_bucket
  ]
}

resource "aws_signer_signing_job" "this" {
  profile_name = aws_signer_signing_profile.this.name

  source {
    s3 {
      bucket  = module.s3_bucket.s3_bucket_id
      key     = aws_s3_object.unsigned.id
      version = aws_s3_object.unsigned.version_id
    }
  }

  destination {
    s3 {
      bucket = module.s3_bucket.s3_bucket_id
      prefix = "signed/"
    }
  }
}

resource "aws_lambda_code_signing_config" "this" {
  allowed_publishers {
    signing_profile_version_arns = [aws_signer_signing_profile.this.arn]
  }

  policies {
    untrusted_artifact_on_deployment = "Enforce"
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name = "parameter-store-api"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_resource" "resource" {
  path_part   = "parameter"
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.api.id
}

resource "aws_api_gateway_request_validator" "this" {
  name                        = "example"
  rest_api_id                 = aws_api_gateway_rest_api.api.id
  validate_request_body       = true
  validate_request_parameters = true
}

resource "aws_api_gateway_method" "method" {
  #checkov:skip=CKV_AWS_59:this example is an unprotected API (publicly accessible)
  #ts:skip=AC_AWS_0439 - public api
  rest_api_id          = aws_api_gateway_rest_api.api.id
  resource_id          = aws_api_gateway_resource.resource.id
  http_method          = "ANY"
  authorization        = "NONE"
  request_validator_id = aws_api_gateway_request_validator.this.id
}

resource "aws_api_gateway_integration" "integration" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.resource.id
  http_method             = aws_api_gateway_method.method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.parameter_store_lambda.invoke_arn
}

# Create a deployment for the API
resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [aws_api_gateway_integration.integration]

  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "test"

  lifecycle {
    create_before_destroy = true
  }
}

# Allow API Gateway to invoke Lambda function
resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.parameter_store_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}
