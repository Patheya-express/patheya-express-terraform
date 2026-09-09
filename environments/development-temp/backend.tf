# This workload deploys into the Security account (512206886196) — see versions.tf's provider
# comment — so its state belongs in that account's own bucket, per bootstrap/main.tf's platform
# standard: one state bucket per AWS account, never shared across accounts. The previous
# Management-account bucket value here was an account-mismatch defect (confirmed via a failed
# real init: Security's role has no cross-account grant on Management's bucket, and none is being
# added — the fix is using the correct account's own bucket, not granting cross-account access).
terraform {
  backend "s3" {
    bucket         = "patheya-express-terraform-state-512206886196"
    key            = "development-temp/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "patheya-express-terraform-locks"
    encrypt        = true
  }
}
