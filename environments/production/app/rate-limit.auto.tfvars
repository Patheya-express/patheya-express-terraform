# Production API rate limit (RATE_LIMIT_MAX) — committed on purpose so the active value is always
# visible in Git. Normal production value: 100.
#
# 2026-10-08: restored to 100 after the controlled k6 capacity test (the temporary 60000 load-test
# override is removed). Any future override must be temporary and reverted the same way.
api_rate_limit_max = 100
