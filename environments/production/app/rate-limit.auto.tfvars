# Production API rate limit (RATE_LIMIT_MAX) — committed on purpose so the active value is always
# visible in Git. Normal production value: 100.
#
# TEMPORARY LOAD-TEST OVERRIDE (2026-10-08): 60000 req/60 s per client IP, so a single k6 load
# generator is not throttled during the controlled capacity test. MUST be set back to 100 (and
# redeployed via backend-deploy-ecs.yml) immediately after the test.
api_rate_limit_max = 60000
