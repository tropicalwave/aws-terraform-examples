data "aws_availability_zones" "available" {}

module "vpc_alb" {
  #checkov:skip=CKV_TF_1:ensure easier readability for examples
  source         = "terraform-aws-modules/vpc/aws"
  name           = "lb-vpc"
  cidr           = "10.0.0.0/16"
  azs            = data.aws_availability_zones.available.names
  public_subnets = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
  version        = ">= 2.0.0"
}

# ECS Cluster
resource "aws_ecs_cluster" "jenkins" {
  name = "jenkins-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


# ECS Task Definition
resource "aws_ecs_task_definition" "jenkins" {
  family                   = "jenkins"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "1024"
  memory                   = "2048"
  track_latest             = true
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name                   = "jenkins"
    image                  = "jenkins/jenkins:2.479.1-lts-alpine"
    readonlyRootFilesystem = true
    portMappings = [{
      containerPort = 8080
      hostPort      = 8080
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/jenkins"
        awslogs-region        = var.region
        awslogs-stream-prefix = "ecs"
      }
    }
    mountPoints = [{
      sourceVolume  = "jenkins-home"
      containerPath = "/var/jenkins_home"
    }]
  }])

  volume {
    name = "jenkins-home"
    efs_volume_configuration {
      transit_encryption = "ENABLED"
      file_system_id     = aws_efs_file_system.jenkins_home.id
    }
  }
}

# ECS Service
resource "aws_ecs_service" "jenkins" {
  name            = "jenkins"
  cluster         = aws_ecs_cluster.jenkins.id
  task_definition = aws_ecs_task_definition.jenkins.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = module.vpc_alb.public_subnets
    security_groups = [aws_security_group.jenkins.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.jenkins.arn
    container_name   = "jenkins"
    container_port   = 8080
  }
}

# Application Load Balancer
resource "aws_lb" "jenkins" {
  #ts:skip=AWS.ALL.IS.MEDIUM.0046
  #checkov:skip=CKV_AWS_91:access logging intentionally disabled
  #checkov:skip=CKV_AWS_150:deletion protection intentionally disabled
  #checkov:skip=CKV2_AWS_20:HTTP used in this example
  #checkov:skip=CKV2_AWS_103:HTTP used in this example
  #checkov:skip=CKV2_AWS_28:WAF not used in this example
  name                       = "jenkins-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = module.vpc_alb.public_subnets
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "jenkins" {
  #checkov:skip=CKV_AWS_378:HTTP used intentionally
  name        = "jenkins-tg"
  port        = 8080
  protocol    = "HTTP"
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

resource "aws_lb_listener" "jenkins" {
  #ts:skip=AWS.ALL.IS.MEDIUM.0046
  #checkov:skip=CKV_AWS_2:HTTP used intentionally
  #checkov:skip=CKV_AWS_20:HTTP used intentionally (no HTTPS redirection)
  #checkov:skip=CKV2_AWS_28:no WAF configured
  #checkov:skip=CKV_AWS_103:no HTTPS enabled
  load_balancer_arn = aws_lb.jenkins.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins.arn
  }
}

# EFS for Jenkins home
resource "aws_efs_file_system" "jenkins_home" {
  #checkov:skip=CKV_AWS_184:encryption with AWS-managed key fine in this example
  creation_token = "jenkins-home"
  encrypted      = true
}

resource "aws_efs_mount_target" "jenkins_home" {
  count           = length(module.vpc_alb.public_subnets)
  file_system_id  = aws_efs_file_system.jenkins_home.id
  subnet_id       = module.vpc_alb.public_subnets[count.index]
  security_groups = [aws_security_group.efs.id]
}

# Security Groups
resource "aws_security_group" "jenkins" {
  name        = "jenkins-sg"
  description = "Security group for Jenkins ECS tasks"
  vpc_id      = module.vpc_alb.vpc_id

  ingress {
    description     = "Allow incoming traffic to Jenkins"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow all outgoing traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "alb" {
  #ts:skip=AC_AWS_0228
  #checkov:skip=CKV_AWS_260:HTTP open to the world by requirement
  name        = "jenkins-alb-sg"
  description = "Security group for Jenkins ALB"
  vpc_id      = module.vpc_alb.vpc_id

  ingress {
    description = "Allow incoming HTTP"
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

resource "aws_security_group" "efs" {
  name        = "jenkins-efs-sg"
  description = "Security group for Jenkins EFS"
  vpc_id      = module.vpc_alb.vpc_id

  ingress {
    description     = "Allow traffic from EFS"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins.id]
  }
}

# CloudWatch Logs
resource "aws_cloudwatch_log_group" "jenkins" {
  #checkov:skip=CKV_AWS_338:log retention period suffices here
  #checkov:skip=CKV_AWS_158:not encrypted with KMS in this example
  name              = "/ecs/jenkins"
  retention_in_days = 30
}
