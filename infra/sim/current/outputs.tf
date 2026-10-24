output "url" {
  value = "http://${aws_lb.this.dns_name}"
}

output "instance_id" {
  value = aws_instance.be.id
}

output "db_host" {
  value = aws_db_instance.this.address
}

output "db_secret_arn" {
  value = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "redis_host" {
  value = aws_elasticache_replication_group.this.primary_endpoint_address
}
