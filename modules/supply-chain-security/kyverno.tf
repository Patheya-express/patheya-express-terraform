# Kyverno — admission controller (validates/mutates on the request path), background controller
# (periodically re-evaluates existing resources so a policy added after a resource was created
# still gets reported against it), cleanup controller (TTL-based resource cleanup — not used by
# any policy in this phase, installed because disabling a chart component this repository has no
# specific reason to disable isn't a real simplification), reports controller (aggregates
# per-resource PolicyReport/ClusterPolicyReport objects, what Section 1's "Reports Controller"
# and Grafana's future policy-compliance dashboard would query).

locals {
  kyverno_replicas = {
    admission_controller  = local.is_production ? 3 : 1 # admission is on the live request path for every pod create in the cluster — production HA matters here specifically
    background_controller = 1
    cleanup_controller    = 1
    reports_controller    = local.is_production ? 2 : 1
  }

  kyverno_values = {
    admissionController = {
      replicas = local.kyverno_replicas.admission_controller
      serviceAccount = {
        annotations = { "eks.amazonaws.com/role-arn" = aws_iam_role.ecr_read["kyverno-admission-controller"].arn }
      }
      # PolicyException support — Section 6's "Policy Exceptions." The exceptions namespace is
      # "kyverno" itself: exceptions are a platform-engineering-reviewed grant, not something an
      # application namespace's own RBAC should be able to self-issue. See docs/exception-
      # process.md for the actual review workflow (a gitops-repo PR, not a raw kubectl apply).
      container = {
        extraArgs = {
          enablePolicyException = "true"
          exceptionNamespace    = "kyverno"
        }
      }
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
      nodeSelector = { "patheya-express.io/node-role" = "system" }
      tolerations  = [{ key = "CriticalAddonsOnly", operator = "Exists" }]
      # HA across zones for the production admission path specifically — a lost AZ must never
      # mean "no admission controller left to evaluate a pod create," which would either block
      # all scheduling (failurePolicy=Fail) or silently stop enforcing policy (failurePolicy=Ignore).
      podDisruptionBudget = {
        enabled      = local.is_production
        minAvailable = local.is_production ? 2 : null
      }
    }

    backgroundController = {
      replicas = local.kyverno_replicas.background_controller
      serviceAccount = {
        annotations = { "eks.amazonaws.com/role-arn" = aws_iam_role.ecr_read["kyverno-background-controller"].arn }
      }
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
      nodeSelector = { "patheya-express.io/node-role" = "system" }
      tolerations  = [{ key = "CriticalAddonsOnly", operator = "Exists" }]
    }

    cleanupController = {
      replicas = local.kyverno_replicas.cleanup_controller
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { cpu = "250m", memory = "256Mi" }
      }
      nodeSelector = { "patheya-express.io/node-role" = "system" }
      tolerations  = [{ key = "CriticalAddonsOnly", operator = "Exists" }]
    }

    reportsController = {
      replicas = local.kyverno_replicas.reports_controller
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
      nodeSelector = { "patheya-express.io/node-role" = "system" }
      tolerations  = [{ key = "CriticalAddonsOnly", operator = "Exists" }]
    }

    # This platform's cluster-wide admission failure mode: never block scheduling if Kyverno
    # itself is unavailable (favors availability of the rest of the platform over strict
    # enforcement during a Kyverno outage) — the same tradeoff every other admission-time
    # control in this repository (Pod Security Admission itself, at the API server level) makes
    # by default. Kyverno's own webhook config exposes this per-policy too (policies-baseline.tf
    # sets failurePolicy explicitly per policy where the tradeoff differs).
    config = {
      resourceFiltersExcludeNamespaces = [
        "kube-system", "kube-node-lease", "kube-public",
      ]
    }

    crds = {
      install = true
    }
  }
}

resource "helm_release" "kyverno" {
  name       = "kyverno"
  namespace  = kubernetes_namespace_v1.security["kyverno"].metadata[0].name
  repository = "https://kyverno.github.io/kyverno"
  chart      = "kyverno"
  version    = "3.3.6"
  wait       = true
  atomic     = true
  timeout    = 600

  values = [yamlencode(local.kyverno_values)]

  depends_on = [kubernetes_resource_quota_v1.security]
}
