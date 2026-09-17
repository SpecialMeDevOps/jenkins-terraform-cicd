output "instance_public_ip" {
  value       = aws_instance.web.public_ip
  description = "Public IP of web server"
}

output "instance_id" {
  value = aws_instance.web.id
}