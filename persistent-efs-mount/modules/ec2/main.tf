terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = ">= 3.3.2"
    }

    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.22.0"
    }

    template = {
      source  = "hashicorp/template"
      version = ">= 2.2.0"
    }
  }
}

# Image data
data "aws_ami" "amzn2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Templates for node initialization (user data)
data "template_file" "mount_efs" {
  template = file("${path.module}/efs-mount.tpl.sh")
  vars = {
    efs_id = aws_efs_file_system.efs.id
  }
}

data "template_file" "associate_eip" {
  template = file("${path.module}/associate-eip.tpl.sh")
  vars = {
    allocation_id = var.one_eip.id
    aws_region    = var.region
  }
}

data "template_cloudinit_config" "config" {
  gzip          = true
  base64_encode = true

  part {
    content_type = "text/x-shellscript"
    content      = data.template_file.mount_efs.rendered
  }

  part {
    content_type = "text/x-shellscript"
    content      = data.template_file.associate_eip.rendered
  }
}

# IAM configuration
resource "aws_iam_role" "ec2_role" {
  name = "${var.namespace}-ec2_role"
  path = "/"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow",
            "Sid": ""
        }
    ]
}
EOF
}

resource "aws_iam_role_policy" "ec2_role_policy" {
  #checkov:skip=CKV_AWS_355:permission cannot be scoped to specific EIP
  #checkov:skip=CKV_AWS_290:permission cannot be scoped to specific EIP
  name = "${var.namespace}-ec2_role_policy"
  role = aws_iam_role.ec2_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ec2:AssociateAddress"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "autoscale_instance_profile" {
  name = "${var.namespace}-autoscale_instance_profile"
  role = aws_iam_role.ec2_role.id
}

# EFS setup
resource "aws_efs_file_system" "efs" {
  # The below uses the KMS default key for EFS encryption for simplicity...
  #ts:skip=AWS.EFS.EncryptionandKeyManagement.High.0409
  #ts:skip=AWS.EFS.EncryptionandKeyManagement.High.0410
  #checkov:skip=CKV_AWS_184:see above
  creation_token   = "${var.namespace}-EFS"
  encrypted        = true
  performance_mode = "generalPurpose"
}

resource "aws_efs_mount_target" "efs_mount" {
  file_system_id  = aws_efs_file_system.efs.id
  security_groups = [var.sg_efs_id]
  count           = length(var.vpc.private_subnets)
  subnet_id       = var.vpc.private_subnets[count.index]
}

# Auto Scaling configuration
resource "aws_launch_template" "ec2_launch_tpl" {
  #checkov:skip=CKV_AWS_88:intentionally associated with public IP
  image_id      = data.aws_ami.amzn2.id
  instance_type = "t3.nano"
  key_name      = var.key_name
  user_data     = base64encode(data.template_cloudinit_config.config.rendered)
  iam_instance_profile {
    arn = aws_iam_instance_profile.autoscale_instance_profile.arn
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [var.sg_ssh_id]
  }
}

resource "aws_autoscaling_group" "ec2_public" {
  desired_capacity = 1
  max_size         = 1
  min_size         = 1

  launch_template {
    id      = aws_launch_template.ec2_launch_tpl.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "persistent-efs-mount"
    propagate_at_launch = true
  }

  vpc_zone_identifier = var.vpc.public_subnets
}
