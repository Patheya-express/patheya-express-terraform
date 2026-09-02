# modules/iam

Per-account identity foundation: GitHub Actions OIDC provider, the Terraform CI deploy role
(scoped policy, not `AdministratorAccess`), and a permission boundary applied to it.

## IRSA roles

EKS IRSA roles (for the AWS Load Balancer Controller, ExternalDNS, cert-manager, External Secrets
Operator, Karpenter) are **not** in this module — they need the EKS cluster's own OIDC provider,
which this module has no dependency on. Those roles are created in `modules/eks-addons`, alongside
each add-on's own Helm release, once `modules/eks` provisions the cluster (and its OIDC provider)
those IRSA roles trust — see `modules/eks-addons/README.md`.

## Usage

Called once per AWS account (management, security, shared-services, development, staging,
production, and — once that account exists — dr) from that account's `environments/*/main.tf`:

```hcl
module "iam" {
  source = "../../modules/iam"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  github_repositories             = ["patheya-express-terraform"]
  terraform_role_allowed_branches = ["ref:refs/heads/main"]
}
```

`backend_ecr_repository_arns`/`frontend_ecr_repository_arns` default to an empty list and only
need to be supplied by the one account that owns the ECR repositories those roles push to
(`environments/shared-services`) — see `github-actions-ci-roles.tf`.

## Security model

- No IAM users, anywhere, ever (enforced by both this module's permission boundary and the
  `deny-root-user-actions`/general least-privilege posture from `modules/organizations`).
- The Terraform CI role's trust policy restricts `sts:AssumeRoleWithWebIdentity` to specific
  repositories AND specific Git refs — a workflow run on a feature branch or from a fork cannot
  assume it, only a run against a protected branch in an allow-listed repo.
- The role's permission policy is scoped to the AWS services this repository's modules actually
  provision, not a blanket grant — see `terraform-role.tf`'s `InfrastructureProvisioning`
  statement for the exact service list.
- IAM role/policy/instance-profile management — for both the Terraform CI role's own policy and
  the permission boundary every Terraform-created role in this account gets — is scoped to this
  account's naming convention (`${var.name_prefix}-*`), not account-wide. `iam:PassRole` in
  particular is scoped the same way: this role can only pass roles this repository's own modules
  create, never an arbitrary role in the account.
- The permission boundary additionally denies creating or re-bounding any role that isn't given
  this same boundary (the standard AWS-documented pattern for preventing a bounded role from
  creating an unbounded one to escalate through), and explicitly denies the classic IAM
  user/group-policy escalation vectors even though nothing in this account has IAM users or groups
  to begin with.
