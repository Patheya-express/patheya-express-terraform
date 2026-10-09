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
  # Decommission-only root (Development is inactive under the four-account policy): pinned to the
  # Development account so it can never run against another one. Do not add resources here.
  allowed_account_ids = ["433985779683"]
}
