terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.32.0"
    }
  }
}

provider "aws" {
    region = var.aws_region

}

terraform {
  backend "s3" {
    bucket         = "github-terraform-project"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}


data "aws_vpc" "default" {
 default = true
  }


resource "aws_security_group" "web_sg" {
    name  = "web_sg"
    description = "Allow inbound traffic for HTTP and SSH, and all outboudnd traffic"
    vpc_id = data.aws_vpc.default.id

  ingress {
    description = "HTTP access"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  } 
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_launch_template" "web_template" {
  name = "web_template"

    image_id = var.ami_id
    instance_type = "t2.micro"
    vpc_security_group_ids = [aws_security_group.web_sg.id]

   user_data = filebase64("${path.module}/user_data.sh")
  }

   data "aws_key_pair" "existing" {
    key_name = var.key_name
}   

resource "aws_lb_target_group" "web-target-group" {
  name     = "web-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id
}

locals {
  selected_subnets = slice(data.aws_subnets.default.ids, 0, 2)
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_lb" "web-alb" {
  name               = "web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.web_sg.id]
  subnets = local.selected_subnets

 



  tags = {
    Environment = "dev"
  }
}
resource "aws_lb_listener" "web_listener" {
  load_balancer_arn = aws_lb.web-alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web-target-group.arn
  }
}

resource "aws_autoscaling_group" "web_asg" {
  name = "web_asg"

  desired_capacity = 2
  min_size         = 2
  max_size         = 4

   wait_for_capacity_timeout = "0"
   
force_delete = true
  vpc_zone_identifier = local.selected_subnets

  health_check_type         = "ELB"
   health_check_grace_period = 300

  target_group_arns = [
    aws_lb_target_group.web-target-group.arn
  ]

  launch_template {
    id      = aws_launch_template.web_template.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "web-asg-instance"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.web_asg.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 50.0
  }
}

data "aws_instances" "asg_instances" {
  instance_tags = {
    "aws:autoscaling:groupName" = aws_autoscaling_group.web_asg.name
  }
}