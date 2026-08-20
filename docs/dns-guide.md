# DNS guide

ExternalDNS (`modules/eks-addons/external-dns.tf`) watches `Ingress`/`Service` objects and writes
matching Route53 records automatically — no manual DNS change on any deploy.

## Scope

`domainFilters` + `zoneIdFilters` restrict ExternalDNS to exactly one zone per cluster: the
environment's own delegated subdomain (`dev.`/`staging.patheyaexpress.com`) for development/staging,
the apex zone (`patheyaexpress.com`) for production — matching
`platform-standards.md` Section 6's "production has no environment prefix." The IRSA policy is
scoped identically (one zone ARN for writes; `ListHostedZones`/`ListTagsForResource` are
necessarily unscoped — Route53 has no per-zone ARN for the list operation itself).

## TXT ownership

`policy = sync` (ExternalDNS may delete records it no longer sees a matching Ingress for) requires
TXT ownership records — `txtOwnerId = <cluster name>`, `txtPrefix = external-dns-`. This is what
lets a manually-created record, or a record from a different tool, coexist without ExternalDNS
assuming it owns and can delete it.

## cert-manager's separate Route53 access

cert-manager's own IRSA role (`cert-manager.tf`) is a **separate** role from ExternalDNS's,
scoped to the same single zone but for `ChangeResourceRecordSets` in service of ACME DNS-01
challenges, not record lifecycle management — two roles, one for each distinct purpose, rather
than one over-broad "anything Route53" role shared between them.
