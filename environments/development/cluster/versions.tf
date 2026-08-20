terraform {
  required_version = "= 1.9.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.76.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "= 4.0.6"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
