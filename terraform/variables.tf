variable "aws_region" {
  default = "ap-south-1"
}

variable "instance_type" {
  default = "t3.micro"
}

variable "environment" {
  default = "prod"
}

variable "deployment_image" {
  description = "Docker image deployed by EC2 user data"
  type        = string
  default     = "malikzohaib1482/workdocker-222:latest"
}
