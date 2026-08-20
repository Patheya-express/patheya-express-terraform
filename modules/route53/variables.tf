variable "tags" {
  type = map(string)
}

variable "zone_name" {
  description = "The domain this zone is authoritative for — \"patheyaexpress.com\" for the apex zone (shared-services account), \"dev.patheyaexpress.com\"/\"staging.patheyaexpress.com\" for delegated per-environment subdomains (platform-standards.md Section 6). Production uses the apex zone directly — no \"prod.\" prefix, per that same standard."
  type        = string
}

variable "create_wildcard_certificate" {
  description = "Requests an ACM certificate covering zone_name and *.zone_name — covers every per-app subdomain (app./restaurant./delivery./admin./api.) under this zone with one certificate, DNS-validated against this same zone."
  type        = bool
  default     = true
}
