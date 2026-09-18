output "instance_public_ip" {
  value       = aws_instance.web.public_ip
  description = "Public IP of web server"
}

output "instance_id" {
  value = aws_instance.web.id
}

output "application_url" {
  value       = "http://${aws_instance.web.public_ip}"
  description = "Public URL of the deployed application"
}