terraform {
  required_version = "= 1.9.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.76.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# DR-region provider — Aurora's AWS Backup cross-region copy destination (main.tf) and that
# vault's own KMS key both live in ap-southeast-1, never ap-south-1 (KMS keys are region-scoped).
# Cross-REGION only, not yet cross-ACCOUNT — see modules/aurora's README and docs/backup-guide.md
# for why the patheya-dr account isn't wired in yet.
provider "aws" {
  alias  = "dr"
  region = var.dr_region
}
