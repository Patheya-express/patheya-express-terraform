# The Production EKS control-plane log group, owned by this persistent root layer rather than by
# cluster/, which is destroyed in idle mode and recreated later (docs/production-lifecycle.md).
# Kept here, the audit/authenticator history of every cluster that has existed survives each
# cluster teardown for the full retention period instead of being deleted with it. EKS delivers
# into /aws/eks/<cluster-name>/cluster by name; cluster/ asserts the names match.

resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${module.shared.name_prefix}/cluster"
  retention_in_days = 90 # matches modules/eks's log_retention_days default the cluster layer used before
  kms_key_id        = module.kms.key_arns["eks-secrets"]

  tags = merge(module.shared.tags, { Application = "eks", Purpose = "control-plane-log-group" })

  lifecycle {
    prevent_destroy = true # retained security evidence — removing it must be a deliberate code change
  }
}
