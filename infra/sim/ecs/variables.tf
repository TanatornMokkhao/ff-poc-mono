variable "name" {
  description = "Prefix of the names this module creates, e.g. ff-poc-mono-staging."
  type        = string
}

variable "existing" {
  description = "Names of what already runs: load balancer, EC2 target group, public subnets (a tag:Name pattern), the box's security group, database, Redis."
  type = object({
    load_balancer       = string
    ec2_target_group    = string
    public_subnet_names = string
    app_security_group  = string
    database            = string
    redis               = string
  })
}

variable "region" {
  type = string
}

variable "boundary_arn" {
  description = "Permissions boundary every role here must carry."
  type        = string
}

variable "ecr_repository_url" {
  type = string
}

variable "ecr_repository_arn" {
  type = string
}

variable "image_tag" {
  description = "Image the first task definitions start with; deploys replace it."
  type        = string
}

variable "runtime_role_arn" {
  description = "Role the be container runs as (the stage's runtime role)."
  type        = string
}

variable "ssm_path" {
  description = "Parameter Store path the be loads its settings from."
  type        = string
}

variable "ecs_weight" {
  description = "Share of requests the listener rule sends to ECS, 0 to 100; the rest go to EC2."
  type        = number
  validation {
    condition     = var.ecs_weight >= 0 && var.ecs_weight <= 100
    error_message = "ecs_weight is a percentage, 0 to 100."
  }
}

variable "worker_count" {
  description = "Worker tasks. 0 until the be has a worker entry point."
  type        = number
}
