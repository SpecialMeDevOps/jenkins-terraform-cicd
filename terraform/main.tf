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

data "aws_subnets" "default_vpc" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
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

resource "aws_security_group" "ssm_endpoints" {
  name        = "${var.environment}-ssm-endpoints"
  description = "Allow EC2 instances to reach AWS Systems Manager endpoints"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.aws_subnets.default_vpc.ids
  security_group_ids  = [aws_security_group.ssm_endpoints.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.aws_subnets.default_vpc.ids
  security_group_ids  = [aws_security_group.ssm_endpoints.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = data.aws_vpc.default.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = data.aws_subnets.default_vpc.ids
  security_group_ids  = [aws_security_group.ssm_endpoints.id]
  private_dns_enabled = true
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
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  iam_instance_profile        = aws_iam_instance_profile.web.name
  vpc_security_group_ids      = [aws_security_group.web_sg.id]
  associate_public_ip_address = true
  depends_on = [
    aws_iam_role_policy_attachment.web_ssm,
    aws_vpc_endpoint.ssm,
    aws_vpc_endpoint.ssmmessages,
    aws_vpc_endpoint.ec2messages
  ]
  user_data_replace_on_change = true

  user_data = <<-EOF
              #!/bin/bash
              set -eux
              exec > >(tee -a /var/log/jenkins-terraform-bootstrap.log | logger -t jenkins-terraform-bootstrap -s 2>/dev/console) 2>&1
              export DEBIAN_FRONTEND=noninteractive
              apt-get update -y
              apt-get install -y docker.io curl
              systemctl enable --now docker
              curl --fail --silent --show-error --location --retry 8 \
                --output /tmp/amazon-ssm-agent.deb \
                "https://s3.${var.aws_region}.amazonaws.com/amazon-ssm-${var.aws_region}/latest/debian_amd64/amazon-ssm-agent.deb"
              dpkg -i /tmp/amazon-ssm-agent.deb
              systemctl daemon-reload
              systemctl enable amazon-ssm-agent
              systemctl restart amazon-ssm-agent
              for attempt in $(seq 1 12); do
                if systemctl is-active --quiet amazon-ssm-agent; then
                  break
                fi
                systemctl restart amazon-ssm-agent || true
                sleep 5
              done
              systemctl is-active --quiet amazon-ssm-agent
              systemctl is-active --quiet docker
              EOF

  tags = {
    Name        = "${var.environment}-web-server"
    Environment = var.environment
  }
}