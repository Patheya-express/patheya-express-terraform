# IAM guide

Full design and usage: `modules/iam/README.md`.

Every account (management, security, shared-services, development, staging, production) gets its
own GitHub Actions OIDC provider and its own Terraform CI role — no cross-account role assumption
chain, no shared credential. A GitHub Actions job targeting a given environment authenticates
directly as that account's own role.

No IAM users exist anywhere in this platform (`platform-standards.md` Section 1, principle 8, and
Section 13) — enforced three ways simultaneously: the SCP `deny-root-user-actions`
(`modules/organizations`), the permission boundary attached to every role (`modules/iam/main.tf`),
and an explicit deny statement in the Terraform CI role's own policy. AWS Config's
`iam-user-no-policies-check` rule (`modules/config/rules.tf`) continuously verifies this holds.

Human access is IAM Identity Center (Section 4's four permission sets), not yet enabled — see
`modules/organizations/README.md`'s manual prerequisites. Until then, break-glass access is the
`OrganizationAccountAccessRole` AWS creates automatically for every member account
(`modules/organizations/main.tf`), used only for the bootstrap sequence in
`docs/bootstrap-guide.md`.
