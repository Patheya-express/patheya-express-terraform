# Architecture overview

This repository implements `cloud-architecture-blueprint.md` Sections 2–7 (AWS Architecture,
Container Platform, Data Platform, Observability) and Section 11 (Security). See the backend
repository's `docs/architecture/cloud-architecture-blueprint.md` and
`docs/architecture/platform-standards.md` for the governing design this repository implements;
this file is a map of *where* each part of that design lives in this codebase, not a restatement
of *why* it's designed that way.

**Phase 0 remediation note**: this table previously marked EKS/Aurora/ElastiCache/ArgoCD/IRSA/
Secrets Manager/image-signing as future-phase work "not in this repository yet." All of it already
exists in this repository's `modules/` and `environments/*/{cluster,data,platform}`. Written and
`terraform validate`-clean is not the same as applied to a real account — see the root
`README.md`'s Scope section for what's genuinely still outstanding (the `dr` account, image-signing
CI, the application-side Redis client change) versus what's simply implemented.

| Blueprint concern | This repository |
| --- | --- |
| Account structure (Section 2) | `modules/organizations`, deployed from `environments/management` |
| Regions/AZs, VPC, DNS/edge (Section 2) | `modules/vpc`, `modules/networking`, `modules/route53` |
| IAM/IRSA (Section 11) | `modules/iam` (OIDC + Terraform CI role, per account) and `modules/eks-addons` (IRSA roles for each add-on, once `modules/eks` provisions the cluster's own OIDC provider) |
| Secrets Manager (Section 11) | `modules/secrets-manager`, consumed by External Secrets Operator (`modules/eks-addons/external-secrets.tf`) |
| KMS (Section 11) | `modules/kms` — one customer-managed key per data class per environment (cloudtrail-logs, ecr, eks-secrets, aurora, redis, secrets, and the DR-region aurora-backup-dr key) |
| Image signing/SBOM/scanning (Section 11) | ECR's own scan-on-push + continuous rescan (`modules/ecr`); Trivy Operator's cluster-wide scanning (`modules/supply-chain-security`); cosign keyless verification is enforced by Kyverno (`modules/supply-chain-security/policies-image-verification.tf`) but has no producing CI pipeline yet — see the root README |
| CloudTrail/Config/GuardDuty/SecurityHub/Access Analyzer (Section 11) | `modules/cloudtrail`, `modules/config`, `modules/security` (including finding-notifications EventBridge/SNS routing) |
| EKS, EKS add-ons, ArgoCD | `modules/eks`, `modules/eks-addons`, `modules/argocd`, deployed from `environments/*/cluster` and `environments/*/platform` |
| Aurora, ElastiCache, Secrets Manager, AWS Backup | `modules/aurora`, `modules/elasticache`, `modules/secrets-manager`, `modules/backup-vault`, deployed from `environments/*/data` |
| Observability, supply-chain security | `modules/observability`, `modules/supply-chain-security`, deployed from `environments/*/platform` |
| Application deployment | **Not this repository** — ArgoCD (above) is the GitOps engine; the applications it deploys are sourced from `patheya-express-platform`/the frontend repo's own `k8s/overlays`, per `modules/argocd/README.md`'s ownership boundary |

See `docs/bootstrap-guide.md` for the actual deployment sequence, and each `modules/*/README.md`
for that module's own design decisions and manual prerequisites.
