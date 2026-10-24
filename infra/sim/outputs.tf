output "url" {
  value = "http://${aws_lb.this.dns_name}"
}

output "cluster" {
  value = aws_ecs_cluster.this.name
}

output "instance_id" {
  value = aws_instance.be.id
}

output "subnets" {
  value = aws_subnet.public[*].id
}

output "app_security_group" {
  value = aws_security_group.app.id
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

output "log_group" {
  value = aws_cloudwatch_log_group.be.name
}

output "exec_role_arn" {
  value = aws_iam_role.exec.arn
}

output "ec2_role_arn" {
  value = aws_iam_role.ec2.arn
}
