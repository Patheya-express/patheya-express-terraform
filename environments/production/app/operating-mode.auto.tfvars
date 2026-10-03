# Production app-layer lifecycle state — see docs/production-lifecycle.md. Committed on purpose so
# a mode change is a reviewed Git change.
#
# "idle" (2026-10-02, Phase A): this layer has never been applied. It requires the data layer's
# state (task definitions reference its secrets), so it is first applied at launch, after data/.
operating_mode = "idle"
