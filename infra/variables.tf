variable "region" {
  type    = string
  default = "ap-southeast-1"
}

# GitHub's immutable OIDC subject of this repo: owner and repo names with their numeric ids, so a
# repo created later under the same name never matches. Read it with:
#   gh api repos/<owner>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix
variable "repo_sub_prefix" {
  type    = string
  default = "repo:TanatornMokkhao@111348335/ff-poc-mono@1430873997"
}

# Stage name in this repo => GitHub Environment the deploy job runs in.
variable "stages" {
  type = map(string)
  default = {
    staging = "staging"
    prod    = "production"
  }
}

# The EC2-to-ECS simulation (sim/). Set in sim.auto.tfvars, so turning it on, moving traffic and
# turning it off are each a one-line pull request with a plan to read.
variable "staging_enabled" {
  type    = bool
  default = false
}

variable "ecs_weight" {
  type    = number
  default = 0
}

variable "ec2_enabled" {
  type    = bool
  default = true
}

variable "api_count" {
  type    = number
  default = 1
}

variable "worker_count" {
  type    = number
  default = 0
}

variable "sim_image_tag" {
  type    = string
  default = "1.2.0-rc.1"
}

# The ECS side of the simulation. false removes it all (the listener rule first), leaving the EC2
# side exactly as before the move: the full rollback.
variable "ecs_enabled" {
  type    = bool
  default = true
}
