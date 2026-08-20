# CloudTrail guide

Full design: `modules/cloudtrail/README.md`.

One organization-wide, multi-region trail with log file validation. Split by design across two
accounts (separation of duties): the trail resource lives in `environments/management` (only the
management account can create an org trail); the S3 destination bucket lives in
`environments/security` (versioned, KMS-encrypted, Glacier-transitioned after a year, bucket
policy scoped to exactly the management account's trail ARN). A CloudWatch Logs feed in the
management account gives real-time queryability alongside the S3 archive's long-term retention.

Data events are captured for S3 object-level access (`event_selector` in
`modules/cloudtrail/trail.tf`) in addition to the default management-event coverage.
