output "wordpress_instance_public_ip" {
  value = aws_instance.wordpress_instance.public_ip
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}