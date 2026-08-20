# modules/alerting

One SNS topic, KMS-encrypted, no subscriptions. Every CloudWatch alarm `modules/aurora` and
`modules/elasticache` create points its `alarm_actions` at this topic's ARN, so a real
notification target exists from day one — deliberately empty of subscribers until Phase 5
(Observability) wires in PagerDuty/Slack, rather than either leaving alarms actionless or
building a premature integration this phase has no scope to configure correctly.

## Inputs

| Name | Description |
| --- | --- |
| `tags` | Standard tag map (platform-standards.md Section 5). |
| `name_prefix` | Environment name prefix, matches every other module. |
| `kms_key_arn` | KMS key encrypting the topic — reuses the environment's own key, no dedicated alerting key. |
| `topic_name` | Suffix, e.g. `alerts-database` → `patheya-<env>-alerts-database`. |

## Outputs

| Name | Description |
| --- | --- |
| `topic_arn` | Pass to `modules/aurora`'s and `modules/elasticache`'s `alarm_sns_topic_arn` input. |

## Why one shared topic, not one per data store

Aurora and ElastiCache alarms are both "the data layer is unhealthy" signals a database
on-call engineer needs in the same place — splitting them into `alerts-aurora`/`alerts-redis`
topics would only matter once different people subscribe to each, which isn't the case at this
phase's scale. Revisit if/when Phase 5's alert routing needs the split.
