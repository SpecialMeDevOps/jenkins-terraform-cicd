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

resource "aws_security_group" "web_sg" {
  name        = "${var.environment}-web-sg"
  description = "Allow HTTP; administration uses AWS Systems Manager"

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

resource "aws_iam_role" "web_ssm" {
  name = "${var.environment}-web-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "web_ssm" {
  role       = aws_iam_role.web_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "web" {
  name = "${var.environment}-web-instance-profile"
  role = aws_iam_role.web_ssm.name
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  iam_instance_profile   = aws_iam_instance_profile.web.name
  vpc_security_group_ids = [aws_security_group.web_sg.id]
  depends_on             = [aws_iam_role_policy_attachment.web_ssm]

  user_data = <<-EOF
              #!/bin/bash
              set -eux
              apt-get update -y
              apt-get install -y docker.io snapd
              systemctl enable --now docker
              systemctl enable --now snapd.socket || true
              for attempt in $(seq 1 12); do
                if snap list amazon-ssm-agent >/dev/null 2>&1; then
                  break
                fi
                snap install amazon-ssm-agent --classic && break || true
                sleep 5
              done
              systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent
              EOF

  tags = {
    Name        = "${var.environment}-web-server"
    Environment = var.environment
  }
}