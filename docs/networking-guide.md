# Networking guide

Full design: `modules/vpc/README.md`, `modules/networking/README.md`.

| Environment | VPC CIDR | NAT strategy |
| --- | --- | --- |
| development | `10.10.0.0/16` | Single shared NAT Gateway (cost tradeoff, dev-only) |
| staging | `10.20.0.0/16` | One NAT Gateway per AZ |
| production | `10.30.0.0/16` | One NAT Gateway per AZ |

Every VPC: 3 AZs (`ap-south-1a/1b/1c`), three subnet tiers (public / private-app / private-data),
private-data has no default route out. Four Security Groups (`nlb`, `eks-node`, `aurora`, `redis`)
created now, attached to real resources starting Phase 3/4. VPC Flow Logs to CloudWatch (KMS
encrypted), 7/30/30-day retention matching each environment's logging standard.

Production does not get its own Route53 zone — see `environments/production/main.tf`'s comment and
`docs/bootstrap-guide.md` Step 8.
