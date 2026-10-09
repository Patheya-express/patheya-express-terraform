# Production DNS cutover — registrar nameservers to Route53

`patheyaexpress.com` currently resolves through the registrar's parking nameservers
(`solar.dns-parking.com`, `lunar.dns-parking.com`, observed 2026-10-02). Production's records
(`api.`, `admin.`, `customer.`, `restaurant.`, `delivery.`) live in the apex hosted zone owned by
`environments/shared-services`, so that zone must become authoritative before any Production ACM
certificate can validate. This is a **manual registrar operation** — nothing in this repository
changes nameservers.

## 1. Inventory what the registrar serves today

Before changing anything, export every record currently served (registrar DNS panel, or
`dig +noall +answer patheyaexpress.com ANY` plus `MX`, `TXT`, `CNAME` for known names such as
`www`). Any record still needed after cutover — **especially MX/SPF/DKIM/DMARC for email** — must
be recreated in the Route53 apex zone first; once nameservers change, the registrar's records stop
resolving.

## 2. Create the apex zone

Apply `environments/shared-services` (reviewed plan, approved apply). Its `route53_apex` module
creates the zone **and** a wildcard ACM certificate whose DNS validation cannot complete until
step 3 — the apply waits on `aws_acm_certificate_validation` (up to 75 minutes). Read the zone's
nameservers while it waits:

```bash
aws route53 list-hosted-zones-by-name --dns-name patheyaexpress.com \
  --query 'HostedZones[0].Id' --output text --profile ReadOnly-668506406019
aws route53 get-hosted-zone --id <zone-id> \
  --query 'DelegationSet.NameServers' --profile ReadOnly-668506406019
```

(after the apply completes, the same four values are the `apex_zone_name_servers` output).

## 3. Change the nameservers at the registrar

In the registrar's control panel for `patheyaexpress.com`, replace the parking nameservers with
exactly the four Route53 nameservers from step 2 (no trailing dots). Do not enable the registrar's
own DNSSEC; if DNSSEC is enabled there, disable it first and wait for the DS record TTL to expire.

## 4. Verify propagation

```bash
dig +short NS patheyaexpress.com @8.8.8.8      # the four awsdns-* nameservers
dig +short NS patheyaexpress.com @1.1.1.1
```

Propagation is governed by the TLD's NS TTL (commonly up to 48 hours, often minutes). Proceed when
public resolvers return the Route53 set.

## 5. Production records

Only after step 4: apply `environments/production/app`. It assumes the shared-services
`patheya-shared-services-production-dns-records-role` (writes limited to Production's five
hostnames and their `_*.` ACM validation records), validates the API certificate (ap-south-1) and
the static-web certificate (us-east-1), and creates the `api.` → ALB and web → CloudFront alias
records.
