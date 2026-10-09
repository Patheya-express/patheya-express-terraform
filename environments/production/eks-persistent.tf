# The retired Production EKS cluster's control-plane log group. EKS is no longer part of
# Production's target architecture (ECS Fargate — ADR-004 as amended); this group is kept, with
# its KMS key (main.tf's eks-secrets), purely as retained security evidence for the audit and
# authenticator history of the cluster that existed 2026-09-25..28. Remove it — a deliberate code
# change, since prevent_destroy blocks anything else — once its retention period has lapsed.

resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${module.shared.name_prefix}/cluster"
  retention_in_days = 90 # matches modules/eks's log_retention_days default the cluster layer used before
  kms_key_id        = module.kms.key_arns["eks-secrets"]

  tags = merge(module.shared.tags, { Application = "eks", Purpose = "control-plane-log-group" })

  lifecycle {
    prevent_destroy = true # retained security evidence — removing it must be a deliberate code change
  }
}
