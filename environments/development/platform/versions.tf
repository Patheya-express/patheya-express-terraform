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

provider "aws" {
  region = var.aws_region
}

# Authenticates via the `aws eks get-token` exec plugin — a short-lived, SigV4-signed token, never
# a stored kubeconfig or static credential (platform-standards.md Section 1, principle 8). This is
# also exactly why this state is a SEPARATE apply from cluster/: these provider blocks need
# data.terraform_remote_state.cluster's outputs to already exist as real values, which they can't
# be on a from-scratch apply of a combined cluster+addons configuration — see the root README.
provider "kubernetes" {
  host                   = data.terraform_remote_state.cluster.outputs.cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster.outputs.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.cluster.outputs.cluster_name, "--region", var.aws_region]
  }
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.cluster.outputs.cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster.outputs.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.cluster.outputs.cluster_name, "--region", var.aws_region]
    }
  }
}
