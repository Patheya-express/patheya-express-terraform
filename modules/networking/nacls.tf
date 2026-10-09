# Defense-in-depth on the private-data tier only (cloud-architecture-blueprint.md Section 2:
# "Security Groups do the real work; NACLs exist to contain a Security-Group misconfiguration, not
# as the primary control"). Public and private-app subnets stay on the VPC's default (allow-all)
# NACL — Security Groups are the enforced boundary there; a second, redundant default-deny NACL on
# every tier would add operational complexity (stateless rule-numbering, both directions) without
# a corresponding security improvement over what the Security Groups in security-groups.tf already
# provide for those two tiers.

resource "aws_network_acl" "private_data" {
  vpc_id     = var.vpc_id
  subnet_ids = var.private_data_subnet_ids

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-private-data-nacl"
    Application = "networking"
    Purpose     = "private-data-network-acl"
  })
}

resource "aws_network_acl_rule" "private_data_ingress_postgres" {
  network_acl_id = aws_network_acl.private_data.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr # coarse VPC-wide allow — the Security Group (aurora-sg) is the actual precise boundary per this file's header comment; this NACL rule only needs to not be wrong, not be tight
  from_port      = 5432
  to_port        = 5432
}

resource "aws_network_acl_rule" "private_data_ingress_redis" {
  network_acl_id = aws_network_acl.private_data.id
  rule_number    = 200
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
  from_port      = 6379
  to_port        = 6379
}

# Ephemeral return-traffic ports — NACLs are stateless, so a response to an allowed inbound
# connection needs its own explicit rule.
resource "aws_network_acl_rule" "private_data_egress_ephemeral" {
  network_acl_id = aws_network_acl.private_data.id
  rule_number    = 100
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.vpc_cidr
  from_port      = 1024
  to_port        = 65535
}

# Return traffic for connections the private-data tier itself opens to another private-data subnet
# (RDS Proxy -> Aurora, both in this tier). The ephemeral-port egress rule above covers outbound
# responses to app-tier clients, but a response arriving back at a data-tier client's ephemeral
# port is inbound traffic and needs its own rule. Scoped to the private-data subnets' own CIDRs,
# never the VPC or the app tier, so it does not open high ports to any other tier. Traffic within a
# single subnet is not evaluated by a NACL, which is why only cross-subnet paths were affected.
data "aws_subnet" "private_data" {
  count = length(var.private_data_subnet_ids)

  id = var.private_data_subnet_ids[count.index]
}

resource "aws_network_acl_rule" "private_data_ingress_ephemeral_from_private_data" {
  count = length(var.private_data_subnet_ids)

  network_acl_id = aws_network_acl.private_data.id
  rule_number    = 300 + count.index
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = data.aws_subnet.private_data[count.index].cidr_block
  from_port      = 1024
  to_port        = 65535
}
