# The "after" side: the api and the worker as separate Fargate services from the same image, as FF
# would run them. Terraform creates them once; every deploy registers a new task definition and
# points the service at it, so the services ignore task_definition here and Terraform never rolls a
# release back.
resource "aws_ecs_cluster" "this" {
  name = var.name
}

data "aws_iam_policy_document" "ecs_tasks_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "pull_and_secret" {
  statement {
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    actions   = ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
    resources = [var.ecr_repository_arn]
  }
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_db_instance.this.master_user_secret[0].secret_arn]
  }
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.be.arn}:*"]
  }
}

# What ECS itself uses to start a task: pull the image, hand the database password to the container,
# open the log stream. The container runs as the runtime role.
resource "aws_iam_role" "exec" {
  name                 = "${var.name}-ecs-exec"
  assume_role_policy   = data.aws_iam_policy_document.ecs_tasks_trust.json
  permissions_boundary = var.boundary_arn
}

resource "aws_iam_role_policy" "exec" {
  role   = aws_iam_role.exec.id
  policy = data.aws_iam_policy_document.pull_and_secret.json
}

locals {
  image = "${var.ecr_repository_url}:${var.image_tag}"
  # What the platform tells the be about where it runs; the rest of its settings come from SSM_PATH.
  environment = [
    { name = "SSM_PATH", value = var.ssm_path },
    { name = "DB_HOST", value = aws_db_instance.this.address },
    { name = "DB_NAME", value = aws_db_instance.this.db_name },
    { name = "DB_USERNAME", value = aws_db_instance.this.username },
    { name = "REDIS_QUEUE_HOST", value = aws_elasticache_replication_group.this.primary_endpoint_address },
    { name = "RUNTIME", value = "ecs" },
  ]
  secrets = [
    { name = "DB_PASSWORD", valueFrom = "${aws_db_instance.this.master_user_secret[0].secret_arn}:password::" },
  ]
  container = {
    image        = local.image
    essential    = true
    environment  = local.environment
    secrets      = local.secrets
    portMappings = [{ containerPort = 3000, protocol = "tcp" }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.be.name
        awslogs-region        = var.region
        awslogs-stream-prefix = "be"
      }
    }
  }
}

resource "aws_ecs_task_definition" "api" {
  family                   = "${var.name}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.exec.arn
  task_role_arn            = var.runtime_role_arn
  container_definitions    = jsonencode([merge(local.container, { name = "be" })])
}

resource "aws_ecs_task_definition" "worker" {
  family                   = "${var.name}-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.exec.arn
  task_role_arn            = var.runtime_role_arn
  container_definitions = jsonencode([merge(local.container, {
    name         = "be"
    command      = ["node", "worker.js"]
    portMappings = []
  })])
}

resource "aws_ecs_service" "api" {
  name                               = "api"
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.api.arn
  launch_type                        = "FARGATE"
  desired_count                      = 1
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 30
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.ecs.arn
    container_name   = "be"
    container_port   = 3000
  }
  lifecycle {
    ignore_changes = [task_definition]
  }
  depends_on = [aws_lb_listener.http]
}

# No load balancer: the worker takes jobs from Redis. A deploy may stop it before the new one starts
# (minimum 0%), so two workers never run the same crons at once.
resource "aws_ecs_service" "worker" {
  name                               = "worker"
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.worker.arn
  launch_type                        = "FARGATE"
  desired_count                      = var.worker_count
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.app.id]
    assign_public_ip = true
  }
  lifecycle {
    ignore_changes = [task_definition]
  }
}
