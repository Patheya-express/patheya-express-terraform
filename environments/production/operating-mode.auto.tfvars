# Production lifecycle state for this layer — see docs/production-lifecycle.md. Committed (not
# gitignored like terraform.tfvars) so every mode change is a reviewed Git change.
#
# "idle" (2026-09-28): Production stopped while the 32-vCPU quota request is pending — no NAT
# Gateways, Tailscale router 0, GitHub runner 0. Cluster/platform/data layers are not deployed.
operating_mode = "idle"
