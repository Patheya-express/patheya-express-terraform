terraform {
  required_version = "= 1.9.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.76.0"
    }
  }

  # Deliberately no backend block — this is the one configuration in the repository that MUST use
  # local state, because it creates the S3 bucket + DynamoDB table every other configuration's
  # remote backend depends on. Chicken-and-egg: bootstrap can't depend on infrastructure it hasn't
  # created yet. See README.md for the one-time-per-account run procedure and where the resulting
  # local .tfstate file goes afterward (out of Git, into the very bucket it just created).
}

provider "aws" {
  region = var.aws_region

  # Phase 2B safety guard: Terraform itself now refuses to plan/apply if the ambient credentials
  # resolve to any account other than the one this run is explicitly targeting via -var
  # account_id — closes the "accidentally operate against Management when intending Security" risk
  # at the tool level, not just operator discipline.
  allowed_account_ids = [var.account_id]

  default_tags {
    tags = {
      Project     = "patheya-express"
      ManagedBy   = "terraform"
      Repository  = "patheya-express-terraform"
      Application = "bootstrap"
      Purpose     = "terraform-remote-state-backend"
    }
  }
}
