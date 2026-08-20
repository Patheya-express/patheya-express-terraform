# modules/iam

Per-account identity foundation: GitHub Actions OIDC provider, the Terraform CI deploy role
(scoped policy, not `AdministratorAccess`), and a permission boundary applied to it.

## Explicitly out of scope for Phase 2

EKS IRSA roles (for the AWS Load Balancer Controller, ExternalDNS, cert-manager, External Secrets
Operator) are **not** in this module — they need the EKS cluster's own OIDC provider, which doesn't
exist until Phase 3. Those roles belong in a Phase 3/6 addition to this module or a dedicated
`modules/irsa`, added when EKS itself is added — not stubbed out speculatively here
(`docs/architecture/platform-standards.md` Section 1, principle 2).

## Usage

Called once per AWS account (management, security, shared-services, development, staging,
production, dr) from that account's `environments/*/main.tf`:

```hcl
module "iam" {
  source = "../../modules/iam"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  github_repositories             = ["patheya-express-terraform"]
  terraform_role_allowed_branches = ["ref:refs/heads/main"]
}
```

## Security model

- No IAM users, anywhere, ever (enforced by both this module's permission boundary and the
  `deny-root-user-actions`/general least-privilege posture from `modules/organizations`).
- The Terraform CI role's trust policy restricts `sts:AssumeRoleWithWebIdentity` to specific
  repositories AND specific Git refs — a workflow run on a feature branch or from a fork cannot
  assume it, only a run against a protected branch in an allow-listed repo.
- The role's permission policy is scoped to the AWS services this repository's modules actually
  provision, not a blanket grant — see `terraform-role.tf`'s `InfrastructureProvisioning`
  statement for the exact service list.
