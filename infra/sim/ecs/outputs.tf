output "cluster" {
  value = aws_ecs_cluster.this.name
}

output "subnets" {
  value = data.aws_subnets.public.ids
}

output "security_group" {
  value = data.aws_security_group.app.id
}

output "log_group" {
  value = aws_cloudwatch_log_group.be.name
}

output "exec_role_arn" {
  value = aws_iam_role.exec.arn
}

output "listener_rule_arn" {
  value = aws_lb_listener_rule.split.arn
}
