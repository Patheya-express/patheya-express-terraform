# Production app-layer lifecycle state — see docs/production-lifecycle.md. Committed on purpose so
# a mode change is a reviewed Git change.
#
# "live" (2026-10-09): API 2-6 and worker 1-3 under target tracking (API CPU 50 % + 1200
# requests/target/min, worker CPU 60 %, memory 75 %), to prove scale-out/in before the bounded
# load test. Root layer is in live (same runtime as build). Rollback: set "build" and re-apply.
operating_mode = "live"
