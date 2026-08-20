# Trivy Operator — continuous, in-cluster scanning of what's actually running (as opposed to
# Phase 2's ECR-native scanning, which covers what's sitting in the registry, pushed or not).
# Both exist and both matter: an image can pass ECR's scan-on-push clean and still be running
# when a new CVE is disclosed against it weeks later — Trivy Operator's periodic rescan is what
# catches that, in-cluster, regardless of registry.

locals {
  trivy_operator_values = {
    serviceAccount = {
      create      = true
      name        = "trivy-operator"
      annotations = { "eks.amazonaws.com/role-arn" = aws_iam_role.ecr_read["trivy-operator"].arn }
    }

    operator = {
      # Every report type this task's Section 5 names: VulnerabilityReports (default, always on),
      # ConfigAuditReports (Pod spec best-practice checks — this is Trivy's own, broader,
      # non-blocking counterpart to policies-baseline.tf's Kyverno admission checks; running both
      # is deliberate — Kyverno blocks new non-compliant creates in patheya-backend/frontend,
      # Trivy reports on configuration drift and on every OTHER namespace this phase's Kyverno
      # policies don't touch at all), RbacAssessmentReports, ClusterComplianceReports (CIS
      # benchmark-style cluster-wide checks).
      configAuditScannerEnabled     = true
      rbacAssessmentScannerEnabled  = true
      infraAssessmentScannerEnabled = true
      vulnerabilityScannerEnabled   = true

      scanJobsConcurrentLimit = local.is_production ? 5 : 2

      metricsFindingsEnabled = true
    }

    trivy = {
      ignoreUnfixed = false # a CVE with no fix yet is still real signal — surfaced, not hidden, in every report
      severity      = "UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL"
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { cpu = "1", memory = "1Gi" } # the scanner itself, not the operator — a full image vulnerability DB scan is genuinely memory-hungry
      }
    }

    # CIS EKS Benchmark cluster-wide compliance report — Section 5's "Cluster Compliance,"
    # generated on a schedule rather than per-admission (a compliance report is a snapshot of the
    # whole cluster's posture, not something meaningful to compute per pod-create).
    compliance = {
      cron = "0 3 * * *" # 03:00 UTC daily — off-peak, well outside the deny-sync-window hours modules/argocd's production AppProject already avoids
    }

    serviceMonitor = {
      enabled = true
    }

    resources = {
      requests = { cpu = "100m", memory = "128Mi" }
      limits   = { cpu = "500m", memory = "256Mi" }
    }

    nodeSelector = { "patheya-express.io/node-role" = "system" }
    tolerations  = [{ key = "CriticalAddonsOnly", operator = "Exists" }]
  }
}

resource "helm_release" "trivy_operator" {
  name       = "trivy-operator"
  namespace  = kubernetes_namespace_v1.security["trivy-system"].metadata[0].name
  repository = "https://aquasecurity.github.io/helm-charts"
  chart      = "trivy-operator"
  version    = "0.24.1"
  wait       = true
  atomic     = true
  timeout    = 600

  values = [yamlencode(local.trivy_operator_values)]

  depends_on = [kubernetes_resource_quota_v1.security]
}
