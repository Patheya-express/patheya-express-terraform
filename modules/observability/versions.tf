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
      version = "~> 3.6"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
