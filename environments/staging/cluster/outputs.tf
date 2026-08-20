output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value     = module.eks.cluster_certificate_authority_data
  sensitive = true
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  value = module.eks.oidc_provider_url
}

output "node_role_name" {
  value = module.eks.node_role_name
}

output "vpc_id" {
  value = data.terraform_remote_state.network.outputs.vpc_id
}

output "private_app_subnet_ids" {
  value = data.terraform_remote_state.network.outputs.private_app_subnet_ids
}

output "eks_node_security_group_id" {
  value = data.terraform_remote_state.network.outputs.eks_node_security_group_id
}

output "route53_zone_id" {
  value = data.terraform_remote_state.network.outputs.route53_zone_id
}

output "acm_certificate_arn" {
  value = data.terraform_remote_state.network.outputs.acm_certificate_arn
}
