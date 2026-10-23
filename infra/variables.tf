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
