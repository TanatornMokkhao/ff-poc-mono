variable "name" {
  description = "Prefix of every resource name, e.g. ff-poc-mono-staging."
  type        = string
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
  description = "Image the first task definition and the EC2 box start with; deploys replace it."
  type        = string
}

variable "runtime_role_arn" {
  description = "Role the be container runs as on ECS (the stage's runtime role)."
  type        = string
}

variable "runtime_policy_json" {
  description = "Policy of the runtime role, given to the EC2 box too so both runtimes read the same settings."
  type        = string
}

variable "ssm_path" {
  description = "Parameter Store path the be loads its settings from."
  type        = string
}

variable "ecs_weight" {
  description = "Share of requests the load balancer sends to ECS, 0 to 100; the rest go to EC2."
  type        = number
  validation {
    condition     = var.ecs_weight >= 0 && var.ecs_weight <= 100
    error_message = "ecs_weight is a percentage, 0 to 100."
  }
}

variable "worker_count" {
  description = "Worker tasks on ECS. 0 until the be has a worker entry point."
  type        = number
}
