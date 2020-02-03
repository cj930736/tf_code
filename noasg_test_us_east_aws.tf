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

resource "aws_internet_gateway" "my_vpc_igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "My VPC - Internet Gateway"
  }
}

resource "aws_route_table" "my_vpc_public" {
    vpc_id = aws_vpc.my_vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.my_vpc_igw.id
    }

    tags = {
        Name = "Public Subnets Route Table for My VPC"
    }
}

resource "aws_route_table_association" "my_vpc_us_east_2a_public" {
    subnet_id = aws_subnet.public_us_east_2a.id
    route_table_id = aws_route_table.my_vpc_public.id
}

resource "aws_route_table_association" "my_vpc_us_east_2b_public" {
    subnet_id = aws_subnet.public_us_east_2b.id
    route_table_id = aws_route_table.my_vpc_public.id
}

resource "aws_route_table_association" "my_vpc_us_east_2c_public" {
    subnet_id = aws_subnet.public_us_east_2c.id
    route_table_id = aws_route_table.my_vpc_public.id
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
  availability_zone = "us-east-2c"

  tags = {
    Name = "Public Subnet us-east-2c"
  }
}

// Create the Security Group which will be used for the EC2 instances launched by the auto-scaling group
resource "aws_security_group" "ec2_sg" {
  name = "ANDdig_WebTier_sg"
  vpc_id = aws_vpc.my_vpc.id

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

resource "aws_instance" "test_web_2a" {

  ami 	        	      = "ami-06249d482a680ae8d"
  instance_type 	      = "t2.nano"
  subnet_id     	      = aws_subnet.public_us_east_2a.id 
  associate_public_ip_address = true
  key_name 		      = "caj_key" 

  vpc_security_group_ids = [
    aws_security_group.ec2_sg.id
  ]
 
  tags = {
    "Terraform" : "true"
  }

} 

resource "aws_instance" "test_web_2b" {

  ami 	         	      = "ami-06249d482a680ae8d"
  instance_type 	      = "t2.nano"
  subnet_id     	      = aws_subnet.public_us_east_2b.id
  associate_public_ip_address = true
  key_name 		      = "caj_key" 

  vpc_security_group_ids = [
    aws_security_group.ec2_sg.id
  ]
 
  tags = {
    "Terraform" : "true"
  }

} 

resource "aws_instance" "test_web_2c" {

  ami 	        	      = "ami-06249d482a680ae8d"
  instance_type 	      = "t2.nano"
  subnet_id     	      = aws_subnet.public_us_east_2c.id
  associate_public_ip_address = true
  key_name 		      = "caj_key" 

  vpc_security_group_ids = [
    aws_security_group.ec2_sg.id
  ]
 
  tags = {
    "Terraform" : "true"
  }

} 


// Create the Security Group for the elastic load balancer instance 
resource "aws_security_group" "elb_sg" {
  name_prefix = "ANDdig_elb_sg-"
  vpc_id = aws_vpc.my_vpc.id

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
  instances          = [
			aws_instance.test_web_2a.id,
			aws_instance.test_web_2b.id,
			aws_instance.test_web_2c.id
		       ]
  subnets 	     = [
			aws_subnet.public_us_east_2a.id,
			aws_subnet.public_us_east_2b.id,
			aws_subnet.public_us_east_2c.id
		       ]

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    interval            = 30
    target              = "HTTP:80/"
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
