terraform {
  required_version = "= 1.9.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.76.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "= 3.9.0" # matches this repository's exact-pin convention (modules/secrets-manager/versions.tf) — the version already resolved in every .terraform.lock.hcl in this repository.
    }
  }
}
