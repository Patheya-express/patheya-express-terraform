output "kyverno_namespace" {
  value = kubernetes_namespace_v1.security["kyverno"].metadata[0].name
}

output "trivy_operator_namespace" {
  value = kubernetes_namespace_v1.security["trivy-system"].metadata[0].name
}

output "falco_namespace" {
  value = kubernetes_namespace_v1.security["falco"].metadata[0].name
}

output "image_verification_policy_name" {
  value = "verify-image-signatures"
}

output "image_verification_enforced" {
  value = var.image_verification_policy_mode == "Enforce"
}
