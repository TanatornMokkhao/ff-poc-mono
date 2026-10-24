# A rehearsal of FF's move from EC2 to ECS (docs/ec2-to-ecs.md). sim/current stands in for what FF
# runs today; sim/ecs is the move, and finds current's pieces by name only, as it would on FF's own
# account. Turned on and off in sim.auto.tfvars.
locals {
  sim_name = "ff-poc-mono-staging"
}

module "current" {
  count  = var.staging_enabled ? 1 : 0
  source = "./sim/current"

  name                = local.sim_name
  boundary_arn        = data.aws_iam_policy.boundary.arn
  ecr_repository_arn  = aws_ecr_repository.be.arn
  runtime_policy_json = data.aws_iam_policy_document.runtime["staging"].json
}

module "ecs" {
  count  = var.staging_enabled && var.ecs_enabled ? 1 : 0
  source = "./sim/ecs"

  name = local.sim_name
  existing = {
    load_balancer       = local.sim_name
    ec2_target_group    = "${local.sim_name}-ec2"
    public_subnet_names = "${local.sim_name}-public-*"
    app_security_group  = "${local.sim_name}-app"
    database            = local.sim_name
    redis               = local.sim_name
  }
  region             = var.region
  boundary_arn       = data.aws_iam_policy.boundary.arn
  ecr_repository_url = aws_ecr_repository.be.repository_url
  ecr_repository_arn = aws_ecr_repository.be.arn
  image_tag          = var.sim_image_tag
  runtime_role_arn   = aws_iam_role.runtime["staging"].arn
  ssm_path           = "/ff-poc-mono/staging/be/"
  ecs_weight         = var.ecs_weight
  api_count          = var.api_count
  worker_count       = var.worker_count
}

# What the staging deploy job adds on top of its usual rights: roll a new task definition out on ECS,
# run the migration as a one-off task, and send the deploy script to the EC2 box. It still can never
# read a setting or the database password; the box and the tasks read those themselves.
data "aws_iam_policy_document" "deploy_sim" {
  count = var.staging_enabled && var.ecs_enabled ? 1 : 0

  statement {
    actions = [
      "ecs:RegisterTaskDefinition", "ecs:DescribeTaskDefinition", "ecs:DescribeServices",
      "ecs:UpdateService", "ecs:RunTask", "ecs:DescribeTasks", "ecs:ListTasks",
    ]
    resources = ["*"]
  }
  statement {
    actions = ["iam:PassRole"]
    resources = [
      aws_iam_role.runtime["staging"].arn,
      module.ecs[0].exec_role_arn,
    ]
  }
  statement {
    actions = ["ssm:SendCommand"]
    resources = [
      "arn:aws:ec2:${var.region}:${local.account}:instance/${module.current[0].instance_id}",
      "arn:aws:ssm:${var.region}::document/AWS-RunShellScript",
    ]
  }
  statement {
    actions   = ["ssm:GetCommandInvocation", "ssm:ListCommandInvocations"]
    resources = ["*"]
  }
  statement {
    actions   = ["ec2:DescribeInstances", "elasticloadbalancing:DescribeTargetHealth", "elasticloadbalancing:DescribeTargetGroups"]
    resources = ["*"]
  }
  statement {
    actions   = ["logs:GetLogEvents", "logs:FilterLogEvents"]
    resources = ["arn:aws:logs:${var.region}:${local.account}:log-group:${module.ecs[0].log_group}:*"]
  }
}

resource "aws_iam_role_policy" "deploy_sim" {
  count  = var.staging_enabled && var.ecs_enabled ? 1 : 0
  name   = "sim"
  role   = aws_iam_role.deploy["staging"].id
  policy = data.aws_iam_policy_document.deploy_sim[0].json
}

output "sim" {
  value = var.staging_enabled ? {
    current = module.current[0]
    ecs     = var.ecs_enabled ? module.ecs[0] : null
  } : null
}

# Everything below moved out of the single module "sim" when it split into current and ecs. These
# blocks keep every resource where it is; delete them once no state still holds module.sim.
moved {
  from = module.sim[0].aws_vpc.this
  to   = module.current[0].aws_vpc.this
}
moved {
  from = module.sim[0].aws_internet_gateway.this
  to   = module.current[0].aws_internet_gateway.this
}
moved {
  from = module.sim[0].aws_subnet.public
  to   = module.current[0].aws_subnet.public
}
moved {
  from = module.sim[0].aws_subnet.private
  to   = module.current[0].aws_subnet.private
}
moved {
  from = module.sim[0].aws_route_table.public
  to   = module.current[0].aws_route_table.public
}
moved {
  from = module.sim[0].aws_route_table_association.public
  to   = module.current[0].aws_route_table_association.public
}
moved {
  from = module.sim[0].aws_security_group.alb
  to   = module.current[0].aws_security_group.alb
}
moved {
  from = module.sim[0].aws_security_group.app
  to   = module.current[0].aws_security_group.app
}
moved {
  from = module.sim[0].aws_security_group.db
  to   = module.current[0].aws_security_group.db
}
moved {
  from = module.sim[0].aws_security_group.redis
  to   = module.current[0].aws_security_group.redis
}
moved {
  from = module.sim[0].aws_lb.this
  to   = module.current[0].aws_lb.this
}
moved {
  from = module.sim[0].aws_lb_listener.http
  to   = module.current[0].aws_lb_listener.http
}
moved {
  from = module.sim[0].aws_lb_target_group.ec2
  to   = module.current[0].aws_lb_target_group.ec2
}
moved {
  from = module.sim[0].aws_lb_target_group_attachment.ec2
  to   = module.current[0].aws_lb_target_group_attachment.ec2
}
moved {
  from = module.sim[0].aws_iam_role.ec2
  to   = module.current[0].aws_iam_role.ec2
}
moved {
  from = module.sim[0].aws_iam_role_policy.ec2
  to   = module.current[0].aws_iam_role_policy.ec2
}
moved {
  from = module.sim[0].aws_iam_instance_profile.ec2
  to   = module.current[0].aws_iam_instance_profile.ec2
}
moved {
  from = module.sim[0].aws_instance.be
  to   = module.current[0].aws_instance.be
}
moved {
  from = module.sim[0].aws_db_subnet_group.this
  to   = module.current[0].aws_db_subnet_group.this
}
moved {
  from = module.sim[0].aws_db_instance.this
  to   = module.current[0].aws_db_instance.this
}
moved {
  from = module.sim[0].aws_elasticache_subnet_group.this
  to   = module.current[0].aws_elasticache_subnet_group.this
}
moved {
  from = module.sim[0].aws_elasticache_replication_group.this
  to   = module.current[0].aws_elasticache_replication_group.this
}
moved {
  from = module.sim[0].aws_ecs_cluster.this
  to   = module.ecs[0].aws_ecs_cluster.this
}
moved {
  from = module.sim[0].aws_lb_target_group.ecs
  to   = module.ecs[0].aws_lb_target_group.ecs
}
moved {
  from = module.sim[0].aws_iam_role.exec
  to   = module.ecs[0].aws_iam_role.exec
}
moved {
  from = module.sim[0].aws_iam_role_policy.exec
  to   = module.ecs[0].aws_iam_role_policy.exec
}
moved {
  from = module.sim[0].aws_ecs_task_definition.api
  to   = module.ecs[0].aws_ecs_task_definition.api
}
moved {
  from = module.sim[0].aws_ecs_task_definition.worker
  to   = module.ecs[0].aws_ecs_task_definition.worker
}
moved {
  from = module.sim[0].aws_ecs_service.api
  to   = module.ecs[0].aws_ecs_service.api
}
moved {
  from = module.sim[0].aws_ecs_service.worker
  to   = module.ecs[0].aws_ecs_service.worker
}
moved {
  from = module.sim[0].aws_cloudwatch_log_group.be
  to   = module.ecs[0].aws_cloudwatch_log_group.be
}
