# EKS-managed add-ons owned by the cluster layer itself (optional — var.managed_addons defaults to
# {}, leaving environments that still adopt them in modules/eks-addons unchanged). Owning them
# here, together with bootstrap_self_managed_addons = false, means a freshly created cluster is
# networked and resolvable before any platform layer runs, and nothing unmanaged is left behind
# for a later layer to adopt with OVERWRITE.
#
# Split by ordering: networking add-ons (vpc-cni, kube-proxy) must exist before any node joins —
# with no self-managed defaults a node never reaches Ready without them — while Deployment-based
# add-ons (coredns) need nodes to schedule onto and would otherwise sit DEGRADED.

resource "aws_eks_addon" "before_compute" {
  for_each = { for name, addon in var.managed_addons : name => addon if addon.before_compute }

  cluster_name         = aws_eks_cluster.this.name
  addon_name           = each.key
  addon_version        = each.value.version
  configuration_values = each.value.configuration_values

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(var.tags, { Application = "eks", Purpose = "managed-addon-${each.key}" })
}

resource "aws_eks_addon" "after_compute" {
  for_each = { for name, addon in var.managed_addons : name => addon if !addon.before_compute }

  cluster_name         = aws_eks_cluster.this.name
  addon_name           = each.key
  addon_version        = each.value.version
  configuration_values = each.value.configuration_values

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = merge(var.tags, { Application = "eks", Purpose = "managed-addon-${each.key}" })

  depends_on = [
    aws_eks_node_group.system,
    aws_eks_node_group.application,
  ]
}
