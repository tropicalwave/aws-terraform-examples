data "aws_availability_zones" "available" {}

resource "random_pet" "this" {
  length = 2
}

module "s3_bucket" {
  #checkov:skip=CKV_TF_1:ensure easier readability for examples
  source        = "terraform-aws-modules/s3-bucket/aws"
  bucket        = "alb-lambda-s3-${random_pet.this.id}"
  force_destroy = true
  version       = "~> 3.0"

  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"
}

module "vpc" {
  #checkov:skip=CKV_TF_1:ensure easier readability for examples
  source          = "terraform-aws-modules/vpc/aws"
  name            = "lb-lambda-vpc"
  cidr            = "10.0.0.0/16"
  azs             = data.aws_availability_zones.available.names
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  version         = ">= 2.0.0"
}

resource "aws_security_group" "alb_sg" {
  #checkov:skip=CKV_AWS_260:HTTP open from Internet by purpose
  name        = "allow_http"
  description = "Allow HTTP inbound traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outgoing traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_s3_object" "index_html" {
  bucket       = module.s3_bucket.s3_bucket_id
  key          = "index.html"
  content_type = "text/html"
  content      = <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome</title>
</head>
<body>
    <h1>Hello from S3!</h1>
    <p>This is a sample index.html file.</p>
</body>
</html>
EOF
}

# Lambda Function
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "s3_retriever" {
  #checkov:skip=CKV_AWS_272:Lambda code signing not used in this example
  #checkov:skip=CKV_AWS_116:no DLQ necessary here
  #checkov:skip=CKV_AWS_173:environment variable is not sensitive
  #checkov:skip=CKV_AWS_117:run lambda function in Lambda VPC
  #checkov:skip=CKV_AWS_50:disable tracing
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "s3-object-retriever"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.13"

  reserved_concurrent_executions = 3

  environment {
    variables = {
      S3_BUCKET = module.s3_bucket.s3_bucket_id
    }
  }
}

# IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "lambda_s3_role"

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

resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "lambda_s3_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          module.s3_bucket.s3_bucket_arn,
          "${module.s3_bucket.s3_bucket_arn}/*"
        ]
      }
    ]
  })
}

# ALB
resource "aws_lb" "my_alb" {
  #checkov:skip=CKV_AWS_91:access logging intentionally disabled
  #checkov:skip=CKV_AWS_150:deletion protection intentionally disabled
  #checkov:skip=CKV2_AWS_20:HTTP used in this example
  #checkov:skip=CKV2_AWS_103:HTTP used in this example
  #checkov:skip=CKV2_AWS_28:WAF not used in this example
  name                       = "my-alb"
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb_sg.id]
  subnets                    = module.vpc.public_subnets
  drop_invalid_header_fields = true
}

# ALB Listener
resource "aws_lb_listener" "front_end" {
  #checkov:skip=CKV_AWS_2:HTTP used intentionally
  #checkov:skip=CKV_AWS_103:no HTTPS enabled
  load_balancer_arn = aws_lb.my_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda.arn
  }
}

# Target Group for Lambda
resource "aws_lb_target_group" "lambda" {
  name        = "lambda-tg"
  target_type = "lambda"
}

# Attach Lambda to Target Group
resource "aws_lb_target_group_attachment" "lambda_attachment" {
  target_group_arn = aws_lb_target_group.lambda.arn
  target_id        = aws_lambda_function.s3_retriever.arn
}

# Allow ALB to invoke Lambda
resource "aws_lambda_permission" "with_lb" {
  statement_id  = "AllowExecutionFromLB"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_retriever.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.lambda.arn
}
