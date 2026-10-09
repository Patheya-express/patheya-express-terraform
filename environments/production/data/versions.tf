terraform {
  required_version = "= 1.9.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.76.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "= 3.9.0" # Phase 0 remediation: matches this repository's exact-pin convention — was the one floating-range exception. Pinned to 3.9.0, the version already resolved in every .terraform.lock.hcl in this repository — not an upgrade.
    }
  }
}

provider "aws" {
  region = var.aws_region
  # Four-account policy guard: Terraform refuses to run if the credentials resolve to any other account.
  allowed_account_ids = ["512297269884"]
}

provider "aws" {
  alias  = "dr"
  region = var.dr_region
  # Four-account policy guard: Terraform refuses to run if the credentials resolve to any other account.
  allowed_account_ids = ["512297269884"]
}
