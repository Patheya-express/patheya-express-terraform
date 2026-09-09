terraform {
  required_version = "= 1.9.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.76.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "= 3.9.0"
    }
  }
}

# No hardcoded profile/assume_role — account targeting stays an operator-credential concern, the
# same convention every other environment in this repository already follows (environments/
# management, environments/security). Whoever runs Terraform here must have credentials for
# account 512206886196 (the Security account) active, NOT the management-account
# PlatformAdministrator profile used for read-only audits elsewhere in this engagement.
provider "aws" {
  region = var.aws_region
}
