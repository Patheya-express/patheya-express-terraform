output "argocd_namespace" {
  value = kubernetes_namespace_v1.argocd.metadata[0].name
}

output "argocd_server_dns" {
  value = "argocd-server.argocd.svc.cluster.local"
}

output "root_application_name" {
  value = "root" # matches root-application.tf's literal metadata.name — not dereferenced from the resource itself to avoid depending on kubernetes_manifest's computed .object attribute for a value already known at plan time
}
