# Alerting guide

Alertmanager's routing tree, receivers, grouping, and inhibition rules are fully configured
(`prometheus-stack.tf`'s `local.alertmanager_config`) — only the Slack webhook URL and PagerDuty
integration key are placeholders, exactly matching this task's explicit "Slack (placeholder
only), PagerDuty (placeholder only)."

## Routing (platform-standards.md Section 12's three severity tiers)

| Severity | Receiver | Notification |
| --- | --- | --- |
| `critical` | `pagerduty-critical` | Pages on-call |
| `warning` | `slack-warnings` | Slack `#patheya-alerts` |
| `info` | `null-receiver` | None — dashboard-only, matches Section 12's "three tiers, no more" |

Grouped by `alertname`/`namespace`/`severity`, `group_wait: 30s`, `group_interval: 5m`,
`repeat_interval: 4h`.

## Inhibition

A firing `critical` alert suppresses a matching `warning` alert for the same `alertname` +
`namespace` — a database that's already paging on `Critical-Aurora-*` doesn't also spam Slack
with the `Warning` version of the same underlying condition.

## Why the credentials are file-based, not inline

Alertmanager's config references `/etc/alertmanager/secrets/alertmanager-slack-webhook/webhook-url`
and `/etc/alertmanager/secrets/alertmanager-pagerduty-key/key` — file paths, not inline values in
the Helm release's own values. `alertmanager.alertmanagerSpec.secrets` (in the same values object)
tells the Prometheus Operator to mount those two Kubernetes Secrets (synced from Secrets Manager
by the same `ClusterSecretStore` Phase 4 installed) into the Alertmanager pod at exactly those
paths. This means the placeholder's *empty* state today doesn't require this config to change
later — populating the secret is the only step needed once a human has a real webhook URL/key.

## Populating the placeholders

```bash
aws secretsmanager put-secret-value \
  --secret-id patheya-express/<environment>/alertmanager-slack-webhook \
  --secret-string '{"webhook-url":"https://hooks.slack.com/services/..."}' \
  --region ap-south-1

aws secretsmanager put-secret-value \
  --secret-id patheya-express/<environment>/alertmanager-pagerduty-key \
  --secret-string '{"key":"<pagerduty-integration-key>"}' \
  --region ap-south-1
```

The JSON key names (`webhook-url`, `key`) matter — they're what the `ExternalSecret`'s
`data[].remoteRef.property` (`alertmanager-secrets.tf`) extracts into the synced Kubernetes
Secret's own key, which is in turn the exact filename Alertmanager's config expects inside the
mounted directory. No Terraform change is needed to activate real alerting once these are set —
External Secrets Operator's `refreshInterval: 1h` picks up the new value automatically.

## Alert naming

`<Severity>-<Service>-<Condition>` (platform-standards.md Section 12) — every alert rule in
`prometheus-rules.tf` follows this exactly: `Critical-ApiGateway-SLOBurnRateFast`,
`Warning-Node-CPUUtilizationHigh`, `Critical-Pod-CrashLoopBackOff`, etc.

## SLO burn-rate alerts specifically

See `docs/prometheus-guide.md` and `docs/sre-operations-guide.md` — the two-window
(fast/slow-burn) pattern and what each one means operationally.
