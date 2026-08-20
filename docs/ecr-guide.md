# ECR guide

Full design: `modules/ecr/README.md`. Deployed once, in `environments/shared-services`.

Five repositories: `patheya-express/api-gateway` (shared by the backend's `worker` Deployment —
one image, per `docs/infrastructure/workers.md` in the backend repo), `patheya-express/customer-app`,
`patheya-express/partner-app`, `patheya-express/delivery-app`, `patheya-express/admin-app`.

Immutable tags, KMS encryption, scan-on-push + continuous rescanning, lifecycle policy (untagged
images expire after 7 days, only the 30 most recent tagged images are retained per repository),
org-wide cross-account pull (no push — that's the application repos' own CI role, added in
Phase 7).
