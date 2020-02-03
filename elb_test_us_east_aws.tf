/* The following terraform configuration will spin up an auto scaling group of web servers, fronted off
   by an elastic load balancer of the classic type. All the compoenents will be injected into the given region of
   an AWS virtual private cloud. The individual web server instances will be based on the Ubuntu 18.04 amazon machine
   image and the auto scaling group they form part of will span three availability zones */

variable "whitelist" {
  type = object({
                  for_http = list(string) 
		  for_ssh  = list(string)
		})
}
variable "min_web_instances" {
  type = number
}
variable "max_web_instances" {
  type = number
}
variable "availability_zones" {
  type = list(string)
}

provider "aws" {
  profile = "default"
  region = "us-east-2"
}

resource "aws_vpc" "my_vpc" {
  cidr_block       = "172.32.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "My VPC"
  }
}

resource "aws_subnet" "public_us_east_2a" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "172.32.0.0/28"
  availability_zone = "us-east-2a"

  tags = {
    Name = "Public Subnet us-east-2a"
  }
}

resource "aws_subnet" "public_us_east_2b" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "172.32.1.0/28"
  availability_zone = "us-east-2b"

  tags = {
    Name = "Public Subnet us-east-2b"
  }
}

resource "aws_subnet" "public_us_east_2c" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = "172.32.2.0/28"
  availability_zone = "us-east-2b"

  tags = {
    Name = "Public Subnet us-east-2c"
  }
}

// Create the Security Group which will be used for the EC2 instances launched by the auto-scaling group
resource "aws_security_group" "ec2_sg" {
  name = "ANDdig_WebTier_sg"

  ingress {
    from_port   = 80 
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.whitelist["for_http"] 
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.whitelist["for_ssh"] 
  }
}

// Create the Launch Configuration which will determine how new EC2 instances are launched
resource "aws_launch_configuration" "ec2_lc" {
  name_prefix     = "web-"
  image_id        = "ami-0fc20dd1da406780b"
  instance_type   = "t2.micro" 
  security_groups = [aws_security_group.ec2_sg.id]

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
  availability_zones   = var.availability_zones
  vpc_zone_identifier  = [
                           aws_subnet.public_us_east_2a.id,
                           aws_subnet.public_us_east_2b.id,
                           aws_subnet.public_us_east_2c.id
			 ] 
  min_size             = var.min_web_instances
  max_size             = var.max_web_instances
  load_balancers       = [aws_elb.elb_lb.name]
  health_check_type    = "ELB"
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
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.whitelist["for_http"]
  }
}



// Creating the ELB
resource "aws_elb" "elb_lb" {
  name               = "ANDdig-elb"
  security_groups    = [aws_security_group.elb_sg.id]
  availability_zones = var.availability_zones


  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
    target              = "HTTPS:443/"
  }

  listener {
    lb_port           = 80 
    lb_protocol       = "http"
    instance_port     = 80 
    instance_protocol = "http"
  }

  tags = {
    functional_group = "WebTier"
  }

}
