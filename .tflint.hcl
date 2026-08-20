plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# AWS-specific ruleset (deprecated arguments, incorrect instance types, etc.) — separate plugin,
# separate version pin, matching this repository's own exact-pin convention for the aws provider
# itself (versions.tf's `version = "= 5.76.0"`, never a floating range).
plugin "aws" {
  enabled = true
  version = "0.35.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

config {
  format = "compact"
}
