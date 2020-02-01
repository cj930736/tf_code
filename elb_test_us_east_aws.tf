/* The following terraform configuration will spin up an auto scaling group of web servers, fronted off
   by an elastic load balancer of the classic type. All the compoenents will be injected into the given region of
   an AWS virtual private cloud. The individual web server instances will be based on the Ubuntu 18.04 amazon machine
   image and the auto scaling group they form part of will span three availability zones */

variable "whitelist" {
  type = object({
                  for_https = list(string) 
		  for_ssh  = list(string)
		})
}
variable "private_key_name" {
  type = string
}
variable "min_web_instances" {
  type = number
}
variable "max_web_instances" {
  type = number
}

provider "aws" {
  profile = "default"
  region = "us-east-1"
}

data "aws_availability_zones" "all" {}

// Create the Security Group which will be used for the EC2 instances launched by the auto-scaling group
resource "aws_security_group" "ec2_sg" {
  name = "ANDdig_WebTier_sg"

  ingress {
    from_port   = 443 
    to_port     = 443 
    protocol    = "tcp"
    cidr_blocks = var.whitelist[for_https] 
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.whitelist[for_ssh] 
  }
}

// Create the Launch Configuration which will determine how new EC2 instances are launched
resource "aws_launch_configuration" "ec2_lc" {
  name_prefix     = "web_tier_lc-"
  image_id        = "ami-04b9e92b5572fa0d1"
  instance_type   = "t2.nano" 
  security_groups = [aws_security_group.ec2_sg.id]
  key_name        = private_key_name

  // the following commands will run when an instance is bootstrapped
  user_data       = file("install_apache.sh")

  lifecycle {
    create_before_destroy = true
  }
}

// Creating the auto scaling group for the web-tier
resource "aws_autoscaling_group" "ec2_asg" {
  name		       = "ANDdig_WebTier-asg"
  launch_configuration = aws_launch_configuration.ec2_lc.id
  availability_zones   = ["us-east-1a","us-east-1b","us-east-1c"]
  vpc_zone_identifier  = [var.ec2_asg_props.zone_list]
  min_size             = var.min_web_instances
  max_size             = var.max_web_instances
  load_balancers       = aws_elb.elb_lb.name
  health_check_type    = "ELB"

  tags {
    functinal_grouping = "WebTier"
  }
}


// Create the Security Group for the elastic load balancer instance 
resource "aws_security_group" "elb_sg" {
  name_prefix = "ANDdig_elb_sg-"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443 
    to_port     = 443 
    protocol    = "tcp"
    cidr_blocks = var.whitelist[for_https]
  }
}



// Creating the ELB
resource "aws_elb" "elb_lb" {
  name_prefix        = "ANDdig_elb-"
  security_groups    = [aws_security_group.elb_sg.id]
  availability_zones = [data.aws_availability_zones.all.names]

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
    target              = "HTTPS:443/"
  }

  listener {
    lb_port           = 443 
    lb_protocol       = "https"
    instance_port     = "443"
    instance_protocol = "https"
  }

  tags {
    functional_group = "WebTier"
  }

}
