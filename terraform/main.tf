data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "web_sg" {
  name        = "${var.environment}-web-sg"
  description = "Allow public HTTP for the Docker web application"
  vpc_id      = data.aws_vpc.default.id

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

  tags = {
    Name        = "${var.environment}-web-sg"
    Environment = var.environment
  }
}

resource "aws_instance" "web" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  associate_public_ip_address = true
  user_data_replace_on_change = true

  user_data = <<-EOF
              #!/bin/bash
              set -eux
              exec > >(tee -a /var/log/jenkins-terraform-bootstrap.log | logger -t jenkins-terraform-bootstrap -s 2>/dev/console) 2>&1
              export DEBIAN_FRONTEND=noninteractive
              apt-get update -y
              apt-get install -y docker.io curl
              systemctl enable --now docker
              for attempt in $(seq 1 12); do
                if docker info >/dev/null 2>&1; then break; fi
                if [ "$${attempt}" -eq 12 ]; then
                  echo "Docker did not become ready" >&2
                  exit 1
                fi
                sleep 5
              done
              docker pull ${var.deployment_image}
              docker stop web 2>/dev/null || true
              docker rm web 2>/dev/null || true
              docker run -d --name web -p 80:80 ${var.deployment_image}
              docker ps --filter name=^/web$ --filter status=running --format '{{.Names}}' | grep -qx web
              EOF

  tags = {
    Name        = "${var.environment}-web-server"
    Environment = var.environment
  }
}