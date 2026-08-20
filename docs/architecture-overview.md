# Architecture overview

This repository implements `cloud-architecture-blueprint.md` Sections 2–3 (AWS Architecture,
Container Platform's networking prerequisites) and Section 11 (Security)'s IAM/KMS/logging
foundation — the "AWS Foundation" phase only. See the backend repository's
`docs/architecture/cloud-architecture-blueprint.md` and `docs/architecture/platform-standards.md`
for the governing design this repository implements; this file is a map of *where* each part of
that design lives in this codebase, not a restatement of *why* it's designed that way.

| Blueprint concern | This repository |
| --- | --- |
| Account structure (Section 2) | `modules/organizations`, deployed from `environments/management` |
| Regions/AZs, VPC, DNS/edge (Section 2) | `modules/vpc`, `modules/networking`, `modules/route53` |
| IAM/IRSA (Section 11, partial) | `modules/iam` — OIDC + Terraform CI role only; EKS IRSA roles are Phase 3/6 |
| Secrets Manager (Section 11) | Not yet — External Secrets Operator's AWS side is Phase 6 |
| KMS (Section 11) | `modules/kms` |
| Image signing/SBOM/scanning (Section 11) | ECR's own scan-on-push + continuous rescan (`modules/ecr`); cosign/Syft/Trivy-in-CI is Phase 7 |
| CloudTrail/Config/GuardDuty/SecurityHub/Access Analyzer (Section 11) | `modules/cloudtrail`, `modules/config`, `modules/security` |
| EKS, Aurora, ElastiCache, ArgoCD, application deployment | **Not in this repository yet** — Phase 3/4/6/7 |

See `docs/bootstrap-guide.md` for the actual deployment sequence, and each `modules/*/README.md`
for that module's own design decisions and manual prerequisites.
