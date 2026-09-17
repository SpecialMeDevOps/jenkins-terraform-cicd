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

variable "deployment_id" {
  description = "Unique Jenkins build identifier used for resource names"
  type        = string
}