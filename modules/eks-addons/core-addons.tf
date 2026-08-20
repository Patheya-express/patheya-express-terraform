# The four addons EKS bootstraps by default on cluster creation (modules/eks) are adopted and
# explicitly version-pinned/configured here — "whatever EKS defaulted to on creation day" is not
# reproducible; a Terraform-managed aws_eks_addon resource is (platform-standards.md Section 1,
# principle 4).

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = var.cluster_name
  addon_name   = "vpc-cni"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # Native NetworkPolicy enforcement (this task's Section 4) — the VPC CNI itself enforces
  # Kubernetes NetworkPolicy objects, no separate policy-engine add-on (Calico, Cilium) needed.
  # Prefix delegation raises pod-per-node density well above the ENI-based default, which matters
  # once Karpenter (karpenter.tf) is bin-packing aggressively for spot cost efficiency.
  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
    env = {
      ENABLE_PREFIX_DELEGATION = "true"
      WARM_PREFIX_TARGET       = "1"
    }
  })

  tags = merge(var.tags, { Application = "eks-addons", Purpose = "vpc-cni" })
}

resource "aws_eks_addon" "coredns" {
  cluster_name = var.cluster_name
  addon_name   = "coredns"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  configuration_values = jsonencode({
    replicaCount = var.environment_tier == "production" ? 3 : 2
    tolerations = [
      {
        key      = "CriticalAddonsOnly"
        operator = "Exists"
        effect   = "NoSchedule"
      }
    ]
    nodeSelector = {
      "patheya-express.io/node-role" = "system"
    }
  })

  tags = merge(var.tags, { Application = "eks-addons", Purpose = "coredns" })
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = var.cluster_name
  addon_name   = "kube-proxy"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(var.tags, { Application = "eks-addons", Purpose = "kube-proxy" })
}
