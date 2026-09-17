variable "aws_region" {
  default = "ap-south-1"
}

variable "instance_type" {
  default = "t3.micro"
}

variable "key_name" {
  description = "jenkins-project"
  type        = string
}

variable "environment" {
  default = "prod"
}
