# What the move to ECS finds already running, by name. Nothing here is owned by this module, so the
# same code points at a real account by changing var.existing; it never edits or replaces these.
data "aws_lb" "this" {
  name = var.existing.load_balancer
}

data "aws_lb_listener" "http" {
  load_balancer_arn = data.aws_lb.this.arn
  port              = 80
}

data "aws_lb_target_group" "ec2" {
  name = var.existing.ec2_target_group
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_lb.this.vpc_id]
  }
  filter {
    name   = "tag:Name"
    values = [var.existing.public_subnet_names]
  }
}

# The EC2 box's own security group. The database and Redis already accept it, so tasks that carry it
# reach both without a single rule changed on the existing side.
data "aws_security_group" "app" {
  name   = var.existing.app_security_group
  vpc_id = data.aws_lb.this.vpc_id
}

data "aws_db_instance" "this" {
  db_instance_identifier = var.existing.database
}

data "aws_elasticache_replication_group" "this" {
  replication_group_id = var.existing.redis
}
