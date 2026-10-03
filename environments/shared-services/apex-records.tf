# Existing patheyaexpress.com records carried over from the registrar's (Hostinger) DNS before the
# nameserver cutover (docs/production-dns-cutover.md) — Google Workspace mail and site verification
# plus the www alias. Values and TTLs are exactly what Hostinger's nameservers served on 2026-10-03.
#
# Deliberately NOT carried over: Hostinger's NS/SOA (Route53 owns its own), the parking-page
# A record (2.57.91.91), and the two obsolete qa./api.qa. ACM validation CNAMEs.
#
# Production's api./admin./customer./restaurant./delivery. records are owned by
# environments/production/app through the production-dns-records role (production-dns.tf), not here.

resource "aws_route53_record" "apex_mx" {
  zone_id = module.route53_apex.zone_id
  name    = "patheyaexpress.com"
  type    = "MX"
  ttl     = 3600
  records = ["1 smtp.google.com."]
}

# One TXT record set per name in Route53: Google site verification and SPF share the apex.
resource "aws_route53_record" "apex_txt" {
  zone_id = module.route53_apex.zone_id
  name    = "patheyaexpress.com"
  type    = "TXT"
  ttl     = 14400
  records = [
    "google-site-verification=ocL6iPdDrSp83tbRTvieh8CukgzO0MxeBASemDDHrqE",
    "v=spf1 include:_spf.google.com ~all",
  ]
}

resource "aws_route53_record" "dmarc" {
  zone_id = module.route53_apex.zone_id
  name    = "_dmarc.patheyaexpress.com"
  type    = "TXT"
  ttl     = 3600
  records = ["v=DMARC1; p=none; rua=mailto:postmaster@patheyaexpress.com, mailto:dmarc@patheyaexpress.com; pct=100; adkim=s; aspf=s"]
}

# Google Workspace DKIM (2048-bit key). A TXT string is limited to 255 bytes, so the value is
# published as two strings (255 + 155), exactly as Hostinger serves it; the embedded \"\" is
# Route53's separator between the two strings of a single record value.
resource "aws_route53_record" "google_dkim" {
  zone_id = module.route53_apex.zone_id
  name    = "google._domainkey.patheyaexpress.com"
  type    = "TXT"
  ttl     = 14400
  records = ["v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAouhdrLidkI3cIzSq8V0GQ6bEPw7T8Jw7Wb4MxUCl5Raoxb28Y3nx6SkkJPWtYHbbs13oLJFMKj/TTBvRX72uFV2u9iBes+33+sb+LH5hAXOd7b4kPfQd+pT7qW+vu39E2OFW+QPdG5LCMB6a39ncEDKFrCN+hDa5IXaHkEcx/k70TRse66wRkdR+HwYo/lrRP\"\"iEyzeecTDqITz8C0JwOhaZvJ32WMAM+PFlIPo8/Aec61iNPLcBY6WmIGL7Ik1KWYZALf+51UmSpUO61Ag2crjQrEa5ojfTkvzKDSkDnxpiFO7wuEmxVvBP9EbI7BVltTI42IfHyx73KvcNBA063iwIDAQAB"]
}

resource "aws_route53_record" "www" {
  zone_id = module.route53_apex.zone_id
  name    = "www.patheyaexpress.com"
  type    = "CNAME"
  ttl     = 300
  records = ["patheyaexpress.com"]
}
