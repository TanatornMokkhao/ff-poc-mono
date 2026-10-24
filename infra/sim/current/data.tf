# Postgres for the be. RDS keeps the master password in Secrets Manager, so it never enters Terraform
# state and the plan role never sees it. Built to be thrown away: no final snapshot, no deletion
# protection. A production database takes the opposite of both.
resource "aws_db_subnet_group" "this" {
  name       = var.name
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_db_instance" "this" {
  identifier                  = var.name
  engine                      = "postgres"
  engine_version              = "16"
  instance_class              = "db.t4g.micro"
  allocated_storage           = 20
  storage_type                = "gp3"
  storage_encrypted           = true
  db_name                     = "app"
  username                    = "app"
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.this.name
  vpc_security_group_ids      = [aws_security_group.db.id]
  publicly_accessible         = false
  backup_retention_period     = 1
  skip_final_snapshot         = true
  deletion_protection         = false
  apply_immediately           = true
}

# Redis for queues, cron locks and the socket event bus, as FF runs it: Valkey, one node.
resource "aws_elasticache_subnet_group" "this" {
  name       = var.name
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id       = var.name
  description                = "be queues, cron locks and socket bus"
  engine                     = "valkey"
  engine_version             = "8.0"
  node_type                  = "cache.t4g.micro"
  num_cache_clusters         = 1
  port                       = 6379
  subnet_group_name          = aws_elasticache_subnet_group.this.name
  security_group_ids         = [aws_security_group.redis.id]
  automatic_failover_enabled = false
  at_rest_encryption_enabled = true
  apply_immediately          = true
}
