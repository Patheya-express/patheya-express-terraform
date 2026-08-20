# KMS guide

Full design: `modules/kms/README.md`.

One customer-managed key per data class per account, automatic annual rotation, alias
`alias/<name_prefix>-<data-class>`. This phase only creates `cloudtrail-logs` (every account, for
VPC Flow Logs + Config + CloudTrail's CloudWatch feed) and `ecr` (shared-services only). `aurora`,
`redis`, and `ebs` keys are added in Phase 3/4 alongside the services that use them — not
provisioned idle ahead of need.
