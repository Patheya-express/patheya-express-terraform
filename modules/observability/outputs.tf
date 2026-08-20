output "grafana_service_dns" {
  value = "kube-prometheus-stack-grafana.monitoring.svc.cluster.local"
}

output "prometheus_service_dns" {
  value = "kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090"
}

output "alertmanager_service_dns" {
  value = "kube-prometheus-stack-alertmanager.monitoring.svc.cluster.local:9093"
}

output "loki_service_dns" {
  value = "loki-gateway.logging.svc.cluster.local"
}

output "tempo_otlp_endpoint" {
  value = "tempo.tracing.svc.cluster.local:4317"
}

output "otel_collector_endpoint" {
  description = "The OTLP endpoint a future NestJS OpenTelemetry SDK integration sends traces/metrics/logs to."
  value       = "otel-collector.observability.svc.cluster.local:4317"
}

output "loki_bucket_name" {
  value = aws_s3_bucket.loki.id
}

output "tempo_bucket_name" {
  value = aws_s3_bucket.tempo.id
}

output "grafana_admin_secret_arn" {
  value = aws_secretsmanager_secret.grafana_admin.arn
}
