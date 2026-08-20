# SRE operations guide

What to do when each alert fires — the on-call-facing companion to `alerting-guide.md`'s
configuration reference.

## SLO burn-rate alerts

| Alert | Meaning | First action |
| --- | --- | --- |
| `Critical-ApiGateway-SLOBurnRateFast` | Error budget burning >14.4x — the whole month's 99.9% SLO budget exhausts in ~2 days at this rate | Check the most recent deploy first (`argocd app history` once Phase 7 exists; until then, the GitOps repo's commit log) — a fast burn is almost always a bad deploy, not organic load |
| `Warning-ApiGateway-SLOBurnRateSlow` | Sustained >6x burn over 6h — real but not yet urgent | Investigate before it escalates; check the Application Overview dashboard's error-rate panel once real traffic exists |
| `Critical-ApiGateway-OrderCreationLatencyHigh` | p95 order-creation latency above the 300ms SLO for 5+ minutes | Check Aurora's CPU/connections dashboard and PgBouncer's pool utilization — a saturated connection pool is the most likely cause given PgBouncer's whole reason for existing (docs/pgbouncer-guide.md) |

## Infrastructure alerts

| Alert | First action |
| --- | --- |
| `Critical-Node-NotReady` | Check `kubectl describe node` for the reason; Karpenter should replace a genuinely failed node automatically — a persistent NotReady despite that is the actual incident |
| `Critical-Pod-CrashLoopBackOff` | `kubectl logs --previous` on the pod; check the Loki dashboard for that pod's last log lines before the crash |
| `Warning-PVC-NearlyFull` / `Critical-PVC-AlmostFull` | Identify which PVC (Prometheus/Alertmanager/Grafana/Loki are the only PVC-backed workloads this phase adds) — Prometheus's own retention/storage-size mismatch is the most likely cause if it's Prometheus's PVC specifically |
| `Warning-Karpenter-NodeProvisioningFailed` | Check Karpenter controller logs (Loki, namespace `kube-system`) for the actual EC2 API error — usually a capacity or quota issue in the requested instance family |
| `Warning-Certificate-ExpiringSoon` / `Critical-Certificate-Expired` | Check cert-manager's own logs and the `ClusterIssuer`'s status — a stuck ACME challenge (DNS propagation, Route53 permission) is the most common cause |
| `Warning-Worker-JobFailed` | Check the `failed` state in BullMQ for that queue — platform-standards.md Section 17's dead-letter policy: a human reviews and either manually retries or explicitly discards, a job is never silently lost |

## Runbook: "Grafana shows no data for a panel that used to work"

1. Check the datasource itself first (`grafana-datasources.tf` — Prometheus/Loki/Tempo/
   CloudWatch), not the panel — a datasource-level outage affects every panel using it at once.
2. For a CloudWatch panel specifically: confirm the Grafana IRSA role
   (`modules/observability/iam.tf`) hasn't drifted — a role/policy change outside Terraform
   (ClickOps) is exactly what platform-standards.md Section 1 forbids and is the most likely
   cause if CloudWatch panels specifically (and only those) go blank.
3. For a Prometheus-scraped panel: check the relevant `ServiceMonitor`/`PodMonitor`
   (`servicemonitors.tf`) is still selecting a real target — a Helm chart upgrade on the
   underlying component (NGINX, cert-manager, etc.) that renames its Service/pod labels breaks
   the selector silently, the same class of "renamed a label, broke a selector nobody reviewed
   against it" issue `docs/irsa-guide.md` already warns about for IRSA service-account names.

## Runbook: "An alert fired but no one was paged"

Check `alerting-guide.md`'s placeholder-secret status first — if
`patheya-express/<environment>/alertmanager-pagerduty-key` has never been populated
(`aws secretsmanager get-secret-value` returns nothing), Alertmanager has nothing to page with.
This is expected, not a bug, until a human runs the `put-secret-value` command that guide
documents.

## What's not covered here

Query-level distributed tracing debugging (once real traces exist, Grafana's Tempo Explore view
plus the trace↔log correlation `observability-guide.md` describes is the entry point) and load
testing against these SLOs (Phase 8's explicit scope, not this phase's).
