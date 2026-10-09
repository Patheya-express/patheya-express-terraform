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
}

# CloudFront viewer certificates must be issued in us-east-1 — a hard CloudFront constraint.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# Production's records in the shared-services apex zone (patheyaexpress.com), through the
# narrowly-scoped role environments/shared-services/production-dns.tf creates: it can write only
# api./admin./customer./restaurant./delivery. and their ACM validation records.
provider "aws" {
  alias  = "dns"
  region = var.aws_region

  assume_role {
    role_arn     = data.terraform_remote_state.network.outputs.shared_services_production_dns_role_arn
    session_name = "patheya-production-app-dns"
  }
}
