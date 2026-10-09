terraform {
  required_version = "= 1.9.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.76.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  # Four-account policy guard: Terraform refuses to run if the credentials resolve to any other account.
  allowed_account_ids = ["512297269884"]
}
