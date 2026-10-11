# Amazon Inspector — ECR scanning activation for this account (Security Hub control Inspector.2).
#
# Production holds no ECR repositories: every image (api-gateway and the four frontends) lives in
# Shared Services, whose registry already runs ENHANCED continuous scanning (modules/ecr), so the
# images Production runs are assessed there. Activating ECR scanning here covers any repository
# ever created in this account and satisfies the control; with no images it bills nothing
# ($0.11 per initial image assessment, $0.01 per rescan, ap-south-1).
#
# ECR only. EC2 (Inspector.1: the Tailscale router) and Lambda (Inspector.3/.4) scanning are
# separate, charge-bearing decisions. Standalone activation, not an Organizations delegated
# administrator: delegating Inspector to the Security account would associate and enable every
# member account and is a separate decision.
resource "aws_inspector2_enabler" "ecr" {
  account_ids    = [data.aws_caller_identity.current.account_id]
  resource_types = ["ECR"]
}
