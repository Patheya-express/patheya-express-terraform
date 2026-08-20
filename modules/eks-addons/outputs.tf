output "nginx_ingress_namespace" {
  value = helm_release.nginx_ingress.namespace
}

output "cert_manager_role_arn" {
  value = aws_iam_role.cert_manager.arn
}

output "karpenter_interruption_queue_arn" {
  value = aws_sqs_queue.karpenter_interruption.arn
}

output "application_namespaces" {
  value = { for k, v in kubernetes_namespace_v1.application : k => v.metadata[0].name }
}

output "default_storage_class" {
  value = kubernetes_storage_class_v1.gp3.metadata[0].name
}

output "external_secrets_role_arn" {
  value = aws_iam_role.external_secrets.arn
}

output "pgbouncer_service_dns" {
  description = "In-cluster DNS name the (not-yet-deployed) application's DATABASE_URL points at — see external-secrets.tf's backend_database_url_external_secret."
  value       = "${kubernetes_service_v1.pgbouncer.metadata[0].name}.${local.pgbouncer_namespace}.svc.cluster.local"
}

output "data_platform_namespace" {
  value = local.pgbouncer_namespace
}
