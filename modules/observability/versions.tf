terraform {
  required_version = "= 1.9.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.76.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "= 2.35.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "= 2.16.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "= 3.9.0" # Phase 0 remediation: matches this repository's exact-pin convention — was the one floating-range exception. Pinned to 3.9.0, the version already resolved in every .terraform.lock.hcl in this repository — not an upgrade.
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
