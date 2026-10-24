# Staging as FF would run it during its move from EC2 to ECS: one load balancer in front of an EC2 box
# and ECS services, with Postgres and Redis behind them. Off by default; see docs/ec2-to-ecs.md.
module "sim" {
  count  = var.staging_enabled ? 1 : 0
  source = "./sim"

  name                = "ff-poc-mono-staging"
  region              = var.region
  boundary_arn        = data.aws_iam_policy.boundary.arn
  ecr_repository_url  = aws_ecr_repository.be.repository_url
  ecr_repository_arn  = aws_ecr_repository.be.arn
  image_tag           = var.sim_image_tag
  runtime_role_arn    = aws_iam_role.runtime["staging"].arn
  runtime_policy_json = data.aws_iam_policy_document.runtime["staging"].json
  ssm_path            = "/ff-poc-mono/staging/be/"
  ecs_weight          = var.ecs_weight
  worker_count        = var.worker_count
}

# What the staging deploy job adds on top of its usual rights: roll a new task definition out on ECS,
# run the migration as a one-off task, and send the deploy script to the EC2 box. It still can never
# read a setting or the database password; the box and the tasks read those themselves.
data "aws_iam_policy_document" "deploy_sim" {
  count = var.staging_enabled ? 1 : 0

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
      module.sim[0].exec_role_arn,
    ]
  }
  statement {
    actions = ["ssm:SendCommand"]
    resources = [
      "arn:aws:ec2:${var.region}:${local.account}:instance/${module.sim[0].instance_id}",
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
    resources = ["arn:aws:logs:${var.region}:${local.account}:log-group:${module.sim[0].log_group}:*"]
  }
}

resource "aws_iam_role_policy" "deploy_sim" {
  count  = var.staging_enabled ? 1 : 0
  name   = "sim"
  role   = aws_iam_role.deploy["staging"].id
  policy = data.aws_iam_policy_document.deploy_sim[0].json
}

output "sim" {
  value = var.staging_enabled ? module.sim[0] : null
}
