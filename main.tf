provider "aws" {
  region = "us-east-1"
  access_key = env.AWS_ACCESS_KEY_ID
  secret_key = env.AWS_SECRET_ACCESS_KEY
  token = env.AWS_SESSION_TOKEN
}

# Create a VPC
resource "aws_vpc" "my_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

# Create an internet gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.my_vpc.id
}

# Create a custom route table
resource "aws_route_table" "custom_rt" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

# Create a subnet
resource "aws_subnet" "my_subnet" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

# Associate subnet with route table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.my_subnet.id
  route_table_id = aws_route_table.custom_rt.id
}

# Create a security group
resource "aws_security_group" "allow_web" {
  vpc_id = aws_vpc.my_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create a network interface with an IP in the subnet
resource "aws_network_interface" "web_nic" {
  subnet_id   = aws_subnet.my_subnet.id
  private_ips = ["10.0.1.50"]

  security_groups = [aws_security_group.allow_web.id]
}

# Assign an elastic IP to the network interface
resource "aws_eip" "one" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.web_nic.id
  associate_with_private_ip = "10.0.1.50"
}

# Find the latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-amd64-server-*"]
  }
}

# Workshop 3 Start
# Creating Multiple Instances
resource "aws_instance" "web" {
  count                       = 2  # Number of instances
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.my_subnet.id
  vpc_security_group_ids      = [aws_security_group.allow_web.id]

  user_data = <<-EOF
                #!/bin/bash
                sudo apt-get update
                sudo apt-get install -y apache2
                sudo systemctl start apache2
                sudo systemctl enable apache2
                cat ${file("./index.html")} | sudo tee /var/www/html/index.html
              EOF

  tags = {
    Name = "web-server"
  }
}

# Creating a additional subnet for Load Balancer
resource "aws_subnet" "my_subnet_2" {
  vpc_id                  = aws_vpc.my_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
}

# Association for my_subnet_2
resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.my_subnet_2.id
  route_table_id = aws_route_table.custom_rt.id
}

# Creating a Load Balancer
resource "aws_lb" "web_lb" {
  name               = "web-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.allow_web.id]
  subnets            = [aws_subnet.my_subnet.id, aws_subnet.my_subnet_2.id]

  enable_deletion_protection = false
}

# Target Group and Listener
resource "aws_lb_target_group" "web_tg" {
  name     = "web-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.my_vpc.id
}

resource "aws_lb_listener" "web_listener" {
  load_balancer_arn = aws_lb.web_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

# Register Instances with Target Group
resource "aws_lb_target_group_attachment" "web_tga" {
  count            = 2
  target_group_arn = aws_lb_target_group.web_tg.arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}

# Output Load Balancer's DNS Name
output "lb_dns_name" {
  value = aws_lb.web_lb.dns_name
}
