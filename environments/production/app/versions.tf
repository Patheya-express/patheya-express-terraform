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

# CloudFront viewer certificates must be issued in us-east-1 — a hard CloudFront constraint.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  # Four-account policy guard: Terraform refuses to run if the credentials resolve to any other account.
  allowed_account_ids = ["512297269884"]
}

# Production's records in the shared-services apex zone (patheyaexpress.com), through the
# narrowly-scoped role environments/shared-services/production-dns.tf creates: it can write only
# api./admin./customer./restaurant./delivery. and their ACM validation records.
provider "aws" {
  alias  = "dns"
  region = var.aws_region
  # Assumes the production DNS-records role in Shared Services, so the guard is that account.
  allowed_account_ids = [var.shared_services_account_id]

  assume_role {
    role_arn     = data.terraform_remote_state.network.outputs.shared_services_production_dns_role_arn
    session_name = "patheya-production-app-dns"
  }
}
