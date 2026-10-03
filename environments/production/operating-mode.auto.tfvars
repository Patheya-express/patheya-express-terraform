# Production lifecycle state for this layer — see docs/production-lifecycle.md. Committed (not
# gitignored like terraform.tfvars) so every mode change is a reviewed Git change.
#
# "build" (2026-10-03): NAT Gateways (one per AZ) and the Tailscale router up, for the Production
# database role bootstrap (docs/production-database-bootstrap.md) and the application phase.
# The data layer is deployed; the app layer is not.
operating_mode = "build"
