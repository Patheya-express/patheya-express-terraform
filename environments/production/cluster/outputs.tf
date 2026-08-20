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

# No route53_zone_id / acm_certificate_arn output here, deliberately — production uses the apex
# zone owned by environments/shared-services, not its own zone (see that environment's main.tf
# comment from Phase 2). platform/ takes those two values as explicit tfvars instead of a remote
# state read, consistent with Phase 2's established stance on same-vs-cross-account state reads
# (this one crosses accounts: production -> shared-services).
