data "aws_availability_zones" "available" {}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/index.js"
  output_path = "lambda_function_payload.zip"
}

module "vpc_alb" {
  #checkov:skip=CKV_TF_1:ensure easier readability for examples
  source          = "terraform-aws-modules/vpc/aws"
  name            = "lb-vpc"
  cidr            = "10.0.0.0/16"
  azs             = data.aws_availability_zones.available.names
  public_subnets  = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24", "10.0.5.0/24"]
  version         = ">= 2.0.0"
}

module "vpc_api" {
  #checkov:skip=CKV_TF_1:ensure easier readability for examples
  source          = "terraform-aws-modules/vpc/aws"
  name            = "api-vpc"
  cidr            = "10.1.0.0/16"
  azs             = data.aws_availability_zones.available.names
  public_subnets  = ["10.1.0.0/24", "10.1.1.0/24", "10.1.2.0/24"]
  private_subnets = ["10.1.3.0/24", "10.1.4.0/24", "10.1.5.0/24"]
  version         = ">= 2.0.0"
}

module "tgw" {
  #checkov:skip=CKV_TF_1:ensure easier readability for examples
  source  = "terraform-aws-modules/transit-gateway/aws"
  version = ">= 2.0.0"

  name = "tgw-alb-api"

  vpc_attachments = {
    vpc1 = {
      vpc_id      = module.vpc_alb.vpc_id
      subnet_ids  = module.vpc_alb.private_subnets
      dns_support = true
    }
    vpc2 = {
      vpc_id      = module.vpc_api.vpc_id
      subnet_ids  = module.vpc_api.private_subnets
      dns_support = true
    }
  }
}

resource "aws_route" "vpc1_to_tgw" {
  count                  = length(module.vpc_alb.private_route_table_ids)
  route_table_id         = module.vpc_alb.private_route_table_ids[count.index]
  destination_cidr_block = module.vpc_api.vpc_cidr_block
  transit_gateway_id     = module.tgw.ec2_transit_gateway_id
}

resource "aws_route" "vpc2_to_tgw" {
  count                  = length(module.vpc_api.private_route_table_ids)
  route_table_id         = module.vpc_api.private_route_table_ids[count.index]
  destination_cidr_block = module.vpc_alb.vpc_cidr_block
  transit_gateway_id     = module.tgw.ec2_transit_gateway_id
}

resource "aws_vpc_endpoint" "api_gateway" {
  vpc_id              = module.vpc_api.vpc_id
  service_name        = "com.amazonaws.${var.region}.execute-api"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = module.vpc_api.private_subnets

  security_group_ids = [aws_security_group.vpc_endpoint.id]
}

resource "aws_security_group" "vpc_endpoint" {
  name        = "vpc-endpoint-sg"
  description = "Security group for VPC Endpoint"
  vpc_id      = module.vpc_api.vpc_id

  ingress {
    description = "Allow HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [module.vpc_api.vpc_cidr_block]
  }

  egress {
    description      = "Allow all outgoing traffic"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

# Lambda Function
resource "aws_iam_role" "lambda_role" {
  name = "lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "my_lambda" {
  #checkov:skip=CKV_AWS_272:code signing not used here (see api-gateway-lambda for an example)
  #checkov:skip=CKV_AWS_116:no DLQ necessary here
  #checkov:skip=CKV_AWS_117:no VPC necessary
  #checkov:skip=CKV_AWS_50:no X-Ray tracing necessary
  function_name                  = "my_lambda_function"
  role                           = aws_iam_role.lambda_role.arn
  handler                        = "index.handler"
  runtime                        = "nodejs20.x"
  filename                       = data.archive_file.lambda.output_path
  source_code_hash               = data.archive_file.lambda.output_base64sha256
  reserved_concurrent_executions = 5
}

resource "aws_api_gateway_rest_api" "private_api" {
  name = "private_api"

  endpoint_configuration {
    types            = ["PRIVATE"]
    vpc_endpoint_ids = [aws_vpc_endpoint.api_gateway.id]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_resource" "proxy" {
  path_part   = "echo"
  parent_id   = aws_api_gateway_rest_api.private_api.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.private_api.id
}

resource "aws_api_gateway_request_validator" "proxy" {
  name                        = "proxy-validator"
  rest_api_id                 = aws_api_gateway_rest_api.private_api.id
  validate_request_body       = true
  validate_request_parameters = true
}

# tfsec:ignore:aws-api-gateway-no-public-access
resource "aws_api_gateway_method" "proxy" {
  #ts:skip=AWS.APGM.IS.LOW.0056
  #checkov:skip=CKV_AWS_59:protection by token
  rest_api_id          = aws_api_gateway_rest_api.private_api.id
  resource_id          = aws_api_gateway_resource.proxy.id
  http_method          = "ANY"
  authorization        = "NONE"
  request_validator_id = aws_api_gateway_request_validator.proxy.id
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = aws_api_gateway_rest_api.private_api.id
  resource_id = aws_api_gateway_method.proxy.resource_id
  http_method = aws_api_gateway_method.proxy.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.my_lambda.invoke_arn
}

resource "aws_api_gateway_deployment" "private_api" {
  depends_on = [aws_api_gateway_integration.lambda]

  rest_api_id = aws_api_gateway_rest_api.private_api.id
  stage_name  = "dev"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_rest_api_policy" "policy" {
  rest_api_id = aws_api_gateway_rest_api.private_api.id

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Deny",
            "Principal": "*",
            "Action": "execute-api:Invoke",
            "Resource": "${aws_api_gateway_rest_api.private_api.execution_arn}*",
            "Condition": {
                "StringNotEquals": {
                    "aws:sourceVpce": "${aws_vpc_endpoint.api_gateway.id}"
                }
            }
        },
        {
            "Effect": "Allow",
            "Principal": "*",
            "Action": "execute-api:Invoke",
            "Resource": "${aws_api_gateway_rest_api.private_api.execution_arn}*"
        }
    ]
}
EOF
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.my_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.private_api.execution_arn}/*/*"
}

resource "aws_security_group" "alb" {
  #checkov:skip=CKV_AWS_260:HTTP open to the world by requirement
  name        = "alb-sg"
  description = "Security group for ALB"
  vpc_id      = module.vpc_alb.vpc_id

  ingress {
    description = "Allow HTTP"
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

resource "aws_lb" "my_alb" {
  #checkov:skip=CKV_AWS_91:access logging intentionally disabled
  #checkov:skip=CKV_AWS_150:deletion protection intentionally disabled
  #checkov:skip=CKV2_AWS_20:HTTP used in this example
  #checkov:skip=CKV2_AWS_103:HTTP used in this example
  #checkov:skip=CKV2_AWS_28:WAF not used in this example
  name                       = "my-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = module.vpc_alb.public_subnets
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "my_target_group" {
  name        = "my-targets"
  port        = 443
  protocol    = "HTTPS"
  vpc_id      = module.vpc_alb.vpc_id
  target_type = "ip"

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 60
    interval            = 300
    matcher             = "200,301,302"
  }
}

resource "aws_lb_listener" "http" {
  #checkov:skip=CKV_AWS_2:HTTP used intentionally
  #checkov:skip=CKV_AWS_20:HTTP used intentionally (no HTTPS redirection)
  #checkov:skip=CKV2_AWS_28:no WAF configured
  #checkov:skip=CKV_AWS_103:no HTTPS enabled
  load_balancer_arn = aws_lb.my_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.my_target_group.arn
  }
}

data "aws_network_interface" "eni" {
  count = length(module.vpc_api.private_subnets)
  id    = tolist(aws_vpc_endpoint.api_gateway.network_interface_ids)[count.index]
}

resource "aws_lb_target_group_attachment" "my_target_attachment" {
  count             = length(data.aws_network_interface.eni)
  target_group_arn  = aws_lb_target_group.my_target_group.arn
  target_id         = data.aws_network_interface.eni[count.index].private_ip
  availability_zone = "all"
  port              = 443
}
