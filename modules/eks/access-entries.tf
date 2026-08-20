# EKS Access Entries — replaces the legacy aws-auth ConfigMap entirely (aws_eks_cluster.this's
# access_config.authentication_mode = "API" in main.tf disables aws-auth-based auth outright).
# Every principal that needs kubectl access, including the Terraform CI role that manages
# modules/eks-addons' Kubernetes/Helm resources, is granted here — in Git, reviewed like any other
# change, never a manual `kubectl edit configmap aws-auth`.

resource "aws_eks_access_entry" "this" {
  for_each = var.access_entries

  cluster_name      = aws_eks_cluster.this.name
  principal_arn     = each.value.principal_arn
  kubernetes_groups = each.value.kubernetes_groups
  type              = "STANDARD"

  tags = merge(var.tags, { Application = "eks", Purpose = "access-entry-${each.key}" })
}

resource "aws_eks_access_policy_association" "this" {
  for_each = merge([
    for entry_key, entry in var.access_entries : {
      for policy_arn in entry.access_policy_arns :
      "${entry_key}-${md5(policy_arn)}" => {
        principal_arn = entry.principal_arn
        policy_arn    = policy_arn
      }
    }
  ]...)

  cluster_name  = aws_eks_cluster.this.name
  principal_arn = each.value.principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.this]
}
