# Ingress guide

`AWS NLB → NGINX Ingress Controller → Applications` — this chain is intentional
(`cloud-architecture-blueprint.md` Section 3) and this phase does not deviate from it: no ALB
Ingress, no per-Ingress-resource load balancer.

## How the NLB gets created

The AWS Load Balancer Controller (`modules/eks-addons/aws-lb-controller.tf`) watches
`Service` objects, not `Ingress` objects, for this purpose — NGINX's own Helm-installed `Service`
(type `LoadBalancer`, annotated `service.beta.kubernetes.io/aws-load-balancer-type: external`) is
what triggers NLB provisioning. Every application `Ingress` resource (the backend repo's
`k8s/base/ingress.yaml`) then routes through that one NLB → NGINX pair, never provisioning its own.

## TLS

Terminates at the NLB using the environment's ACM certificate (`module.route53`, Phase 2) — set via
the NGINX Service's `aws-load-balancer-ssl-cert` annotation. NGINX itself receives plain HTTP from
the NLB (a private-subnet-to-private-subnet hop inside the VPC).

## Sticky sessions / WebSocket

Both already exist, unchanged, in the backend repository's `k8s/base/ingress.yaml`
(`nginx.ingress.kubernetes.io/affinity: cookie`, long `proxy-read-timeout`/`proxy-send-timeout`) —
this phase installs the controller those annotations target; it does not re-implement or duplicate
them. See the Phase 3 final report's Section 15 analysis for the full reuse breakdown.

## High availability

`controller.replicaCount` (2 in dev/staging, 3 in production) + a PodDisruptionBudget
(`minAvailable` 1 or 2) + pinned to the `system` node group (never spot-interruptible).

## Health probes

The chart's own `/healthz` liveness/readiness probes, with a slightly longer
`initialDelaySeconds` for a cold-starting pod on a freshly-Karpenter-provisioned node.
