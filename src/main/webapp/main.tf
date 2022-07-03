# deploying a highly available website using data sources to look up ami
# use multiple availability_zones
# by Paul Fomenji Peniel
# ----------------------

prodiver "aws" {
  region = "us-east-1"
}

data "aws_availability_zones" "working" {}
data "aws_ami" "health-ami" {
  owners      = ["360578367177"]
  most_recent = true
  filter {
    name   = "name"
    values = ["health-ami"]
  }
}

resource "aws_default_subnet" "default_az1" {
  availability_zone = data.aws_availability_zones.working.names[0]
}

resource "aws_default_subnet" "default_az2" {
  availability_zone = data.aws_availability_zones.working.names[1]
}

resource "aws_launch_configuration" "web" {
  name_prefix     = "highly-available"
  image_id        = data.aws_ami.health-ami.id
  instance_type   = "t2.micro"
  key_name        = "devops-keypair"
  security_groups = [aws_security_group.web-sg.id]
  #user_data = file(user_data.sh)  // won't be needing because my ami has the necessary packages installed. But you need yours lol

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "web" {
  name                 = "ASG-${aws_launch_configuration.web.name}"
  launch_configuration = aws_launch_configuration.web.name
  min_size             = 2
  max_size             = 2
  min_elb_capacity     = 2
  health_check_type    = "ELB"
  vpc_zone_identifier  = [aws_default_subnet.default_az1.id, aws_default_subnet.default_az2.id]
  load_balancers       = [aws_elb.web-elb.name]

}

resource "aws_elb" "web-elb" {
  name               = "webserver-elb"
  availability_zones = [data.aws_availability_zones.working.names[0], data.aws_availability_zones.working.names[1]]
  security_groups    = [aws_security_group.web-sg.id]
  listener {
    lb_port           = 80
    lb_protocol       = "http"
    instance_port     = 80
    instance_protocol = "http"
  }

  health_check { // target groups
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 10
  }

  tags = {
    name  = "WEB-ELB"
    Owner = "Paul"
  }
}


resource "aws_vpc" "web-vpc" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    name       = "Web-VPC"
    Owner      = "Paul"
    Enviroment = "Prod"
  }
}

resource "aws_subnet" "web-pub1" {
  vpc_id     = aws_vpc.web-vpc.id
  cidr_block = "10.10.0.0/24"

  tags = {
    name       = "Web-Pub1"
    Owner      = "Paul"
    Enviroment = "Prod"
  }
}

resource "aws_internet_gateway" "web-igw" {
  vpc_id = aws_vpc.web-vpc.id

  tags = {
    name = "Web-Igw"
  }
}

resource "aws_route_table" "web-rt" {
  vpc_id = aws_vpc.web-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.web-igw.id
  }

  tags = {
    name = "web-rt"
  }
}

resource "aws_route_table_association" "web-rt-assoc" {
  subnet_id      = aws_subnet.web-pub1.id
  route_table_id = aws_route_table.web-rt.id
}

resource "aws_security_group" "web-sg" {
  name        = "ELB-SG"
  description = "route traffic from web to ec2 instances"
  dynamic "ingress" {
    for_each = ["80", "443"]
    content {
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  ingress {
    description = "to allow ssh"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
