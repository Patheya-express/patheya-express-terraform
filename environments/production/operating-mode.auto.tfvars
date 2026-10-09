# Production lifecycle state for this layer — see docs/production-lifecycle.md. Committed (not
# gitignored like terraform.tfvars) so every mode change is a reviewed Git change.
#
# "live" (2026-10-09): same root runtime as build (NAT Gateways per AZ, Tailscale router 1); set
# so root and app declare the same mode. Approved with the app layer's live autoscaling bounds.
operating_mode = "live"
