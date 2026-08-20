# NGINX Ingress Controller — the single entry point for all HTTP(S)/WebSocket traffic
# (cloud-architecture-blueprint.md Section 3). Its own Service is annotated for the AWS Load
# Balancer Controller (aws-lb-controller.tf) to provision exactly one internet-facing NLB in front
# of it — this is the "AWS NLB -> NGINX -> Applications" chain the task's Section 6 explicitly
# says not to replace with ALB Ingress.
#
# The backend repository's own k8s/base/ingress.yaml (nginx.ingress.kubernetes.io/affinity=cookie,
# WebSocket-friendly proxy timeouts, ingressClassName: nginx) is NOT duplicated here — that
# Ingress *resource* is an application-repo concern (Phase 7 GitOps), already written, already
# correct, and directly reusable unchanged against this controller with zero modification. This
# module only installs the controller itself.

resource "helm_release" "nginx_ingress" {
  name             = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.11.3"
  wait             = true
  atomic           = true

  set {
    name  = "controller.ingressClassResource.name"
    value = "nginx"
  }
  set {
    name  = "controller.ingressClassResource.default"
    value = "true"
  }

  set {
    name  = "controller.replicaCount"
    value = var.environment_tier == "production" ? 3 : 2
  }

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
    value = "external"
  }
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-nlb-target-type"
    value = "ip"
  }
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-scheme"
    value = "internet-facing"
  }
  # TLS terminates at the NLB using the environment's ACM certificate (module.route53, Phase 2) —
  # NGINX itself receives plain HTTP from the NLB on this port, matching the "Cloudflare Full
  # (strict)" hop-encryption model the blueprint's Section 2 already documents (the NLB<->NGINX
  # hop is inside the VPC, private-subnet-to-private-subnet).
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-ssl-cert"
    value = var.acm_certificate_arn
  }
  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-ssl-ports"
    value = "443"
  }

  # Preserves the real client IP through the NLB (target-type=ip, above) for the CORS/rate-limit
  # logic the backend's main.ts already implements against `trust proxy` — see
  # docs/infrastructure/README.md in the backend repo.
  set {
    name  = "controller.config.use-proxy-protocol"
    value = "false" # NLB target-type=ip + externalTrafficPolicy=Local already preserves source IP without needing PROXY protocol's extra hop-by-hop negotiation
  }
  set {
    name  = "controller.service.externalTrafficPolicy"
    value = "Local"
  }

  # WebSocket support needs no special controller flag (NGINX Ingress proxies Upgrade/Connection
  # headers by default) — only the Ingress resource's own proxy-read/send-timeout annotations
  # matter, which is exactly what the backend repo's existing ingress.yaml already sets.

  set {
    name  = "controller.podDisruptionBudget.enabled"
    value = "true"
  }
  set {
    name  = "controller.podDisruptionBudget.minAvailable"
    value = var.environment_tier == "production" ? 2 : 1
  }

  set {
    name  = "controller.nodeSelector.patheya-express\\.io/node-role"
    value = "system"
  }
  set {
    name  = "controller.tolerations[0].key"
    value = "CriticalAddonsOnly"
  }
  set {
    name  = "controller.tolerations[0].operator"
    value = "Exists"
  }

  # Startup/readiness/liveness probes — the chart's own defaults already probe NGINX's
  # /healthz endpoint; overridden here only to lengthen the readiness period slightly for a
  # cold-starting pod on a freshly-scaled node, not to change the probe path/mechanism itself.
  set {
    name  = "controller.readinessProbe.initialDelaySeconds"
    value = "10"
  }
  set {
    name  = "controller.livenessProbe.initialDelaySeconds"
    value = "10"
  }

  set {
    name  = "controller.metrics.enabled"
    value = "true" # scraped by Phase 5's Prometheus — the metric endpoint exists now, nothing scrapes it yet
  }
}
