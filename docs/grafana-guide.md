# Grafana guide

Bundled subchart of `kube-prometheus-stack` (`prometheus-stack.tf`), not a separate `helm_release`
— avoids a second Prometheus Operator CRD install and keeps one Helm release owning the whole
monitoring-namespace lifecycle.

## Stateless by design

`persistence.enabled: false`. Every datasource (`grafana-datasources.tf`), dashboard
(`grafana-dashboards.tf`), and folder is provisioned from Terraform-managed `ConfigMap`s, picked
up live by Grafana's own sidecar containers (`sidecar.dashboards`/`sidecar.datasources`) — no
Helm upgrade needed to change a dashboard, just a `ConfigMap` update.

**Consequence**: anything created by hand in the Grafana UI (a manually-built dashboard, an
edited datasource) does **not** survive a pod restart. This is the deliberate trade platform-
standards.md Section 12 calls for ("a Grafana JSON model is committed to the observability
repo/ConfigMap, not click-configured in the UI and left there") — not an oversight. If a
UI-created dashboard is worth keeping, export its JSON and add it as a new entry in
`modules/observability/grafana-dashboards.tf`'s `local.dashboards` map in a PR, the same review
path every other change in this repository goes through.

## Admin credential

Terraform-generated (`secrets.tf`'s `random_password`), stored in Secrets Manager, synced into
the cluster via the **same** `ClusterSecretStore` Phase 4's External Secrets Operator already
installed — no separate ESO instance, no separate store. Retrieve it:

```bash
aws secretsmanager get-secret-value \
  --secret-id patheya-express/<environment>/grafana-admin \
  --region ap-south-1 --query SecretString --output text | jq -r .password
```

## Access

No `Ingress` for Grafana in this phase — reach it via:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

Exposing Grafana externally (through the existing NGINX Ingress, with real authentication in
front of it) is reasonable future work, not built here — this task's scope didn't ask for it, and
adding it without deciding the auth story first would just open an unauthenticated dashboard to
the internet.

## SSO — ready, not active

`grafana.ini`'s `auth.generic_oauth` block is present and structurally correct
(`prometheus-stack.tf`'s `kube_prometheus_stack_values` local) but `enabled: false` — this task's
Section 3 asked for "SSO-ready configuration," not a live IdP integration, and no IdP has been
chosen yet (IAM Identity Center, gated behind Phase 2's `enable_identity_center`, is the most
likely candidate given it's already in this platform). To activate: set `enabled: true` and
supply `client_id`/`client_secret`/`auth_url`/`token_url`/`api_url` for the chosen IdP.

## Folders and datasources

3 folders (`grafana_folder` annotation, read by the dashboard sidecar): **Infrastructure**
(cluster/node/K8s-health/ingress/networking/storage/certificates), **Data Platform** (Aurora/
Redis/PgBouncer), **Applications** (the placeholder Application Overview dashboard). 5
datasources (`grafana-datasources.tf`): Prometheus (default), Alertmanager, Loki, Tempo,
CloudWatch (IRSA-scoped read-only).

## RBAC

The chart's own default `ClusterRole`/`RoleBinding`s (least-privilege, scoped to what the
Prometheus Operator and Grafana's sidecars actually need to watch) — not hand-rolled or widened
in this repository.
