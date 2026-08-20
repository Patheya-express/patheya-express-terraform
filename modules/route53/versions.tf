terraform {
  required_version = "= 1.9.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.76.0"
    }
  }
}

# Note: CloudFront's own certificate (when Section 7's future S3-backed static path is actually
# built, cloud-architecture-blueprint.md Section 7) requires an ACM certificate in us-east-1
# regardless of the distribution's own region — deliberately not accommodated here with provider
# aliasing, since CloudFront isn't in scope yet (platform-standards.md Section 1, principle 2: not
# built ahead of the need). Add a us-east-1-aliased provider to this module's versions.tf when that
# work actually starts.
