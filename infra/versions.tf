terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Bucket and region come from the Terraform workflow (bucket made by bootstrap/).
  backend "s3" {
    key          = "mono/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = var.region
  # The POC's own account. Credentials for any other account (a client's included) fail before a
  # single call, so a wrong profile can never plan or apply anything elsewhere.
  allowed_account_ids = ["375355731232"]
}
