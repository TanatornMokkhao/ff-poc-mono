variable "name" {
  description = "Prefix of every resource name, e.g. ff-poc-mono-staging. The ECS side finds these by it."
  type        = string
}

variable "boundary_arn" {
  description = "Permissions boundary every role here must carry."
  type        = string
}

variable "ecr_repository_arn" {
  type = string
}

variable "runtime_policy_json" {
  description = "Policy of the stage's runtime role, so the box reads the same settings ECS tasks do."
  type        = string
}
