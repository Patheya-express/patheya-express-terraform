# Production app-layer lifecycle state — see docs/production-lifecycle.md. Committed on purpose so
# a mode change is a reviewed Git change.
#
# "build" (2026-10-06): API 1/1 and worker 1/1 for the first Production backend deployment
# (backend-deploy-ecs.yml, release 0.1.0-7a4f7dc). Root layer is already in build (NAT up).
operating_mode = "build"
