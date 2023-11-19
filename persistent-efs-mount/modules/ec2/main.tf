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
  }
}

data "aws_ami" "amzn2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

#data "template_file" "mount_efs" {
#  template = file("efs-mount.tpl")
#  vars = {
#    efs_id = aws_efs_file_system.efs.id
#  }
#}

resource "aws_efs_file_system" "efs" {
  creation_token   = "EFS Shared Data"
  encrypted        = true
  performance_mode = "generalPurpose"
}

resource "aws_efs_mount_target" "efs_mount" {
  file_system_id  = aws_efs_file_system.efs.id
  security_groups = [var.sg_efs_id]
  count           = length(var.vpc.private_subnets)
  subnet_id       = var.vpc.private_subnets[count.index]
}

resource "aws_launch_template" "ec2_launch_tpl" {
  image_id               = data.aws_ami.amzn2.id
  instance_type          = "t2.nano"
  vpc_security_group_ids = [var.sg_ssh_id]
  #user_data              = data.template_file.mount_efs.rendered
}

resource "aws_autoscaling_group" "ec2_public" {
  desired_capacity = 1
  max_size         = 1
  min_size         = 1
  launch_template {
    id      = aws_launch_template.ec2_launch_tpl.id
    version = "$Latest"
  }

  vpc_zone_identifier = var.vpc.public_subnets
}
