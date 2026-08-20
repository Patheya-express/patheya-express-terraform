output "application_namespaces" {
  value = module.eks_addons.application_namespaces
}

output "default_storage_class" {
  value = module.eks_addons.default_storage_class
}

output "grafana_service_dns" {
  value = module.observability.grafana_service_dns
}

output "otel_collector_endpoint" {
  value = module.observability.otel_collector_endpoint
}

output "argocd_server_dns" {
  value = module.argocd.argocd_server_dns
}

output "image_verification_enforced" {
  value = module.supply_chain_security.image_verification_enforced
}
