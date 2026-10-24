# The EC2-to-ECS simulation. Each change is a pull request: read the plan, merge, approve "infra".
staging_enabled = false
ecs_enabled     = true
ec2_enabled     = false
ecs_weight      = 100
api_count       = 2
worker_count    = 0
