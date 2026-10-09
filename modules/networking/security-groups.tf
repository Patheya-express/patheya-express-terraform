# The four Security Groups from cloud-architecture-blueprint.md Section 2's table, created now as
# the networking foundation even though nothing attaches to eks-node-sg/aurora-sg/redis-sg until
# Phase 3/4 — a Security Group is a free, VPC-scoped ACL object with no resource behind it yet to
# provision ahead of need; unlike a KMS key (modules/kms) or an actual EKS/Aurora/Redis resource,
# there's no idle-cost or premature-commitment argument against defining the network policy now so
# later phases attach to an already-reviewed boundary instead of inventing one under deploy pressure.
#
# The NLB, EKS-node and EKS-fronted Redis groups (and every rule referencing them) are gated behind
# var.create_eks_topology_security_groups (default true, so every existing caller is unchanged).
# Production sets it false: its runtime is ECS Fargate (ECS topology section below), and those
# groups would otherwise remain as unattached, misleading network policy. The aurora group is NOT
# gated — it is attached to the Aurora cluster itself in every environment that has one.

resource "aws_security_group" "nlb" {
  count = var.create_eks_topology_security_groups ? 1 : 0

  name_prefix = "${var.name_prefix}-nlb-"
  description = "AWS NLB - the single internet-facing entry point (cloud-architecture-blueprint.md Section 1)."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-nlb-sg"
    Application = "networking"
    Purpose     = "nlb-security-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# Phase 0 remediation (cloud-architecture-blueprint.md Section 2's footnote, ADR-004): one rule
# per Cloudflare CIDR block from var.nlb_allowed_cidrs, replacing the previous unconditional
# 0.0.0.0/0 rule whose real narrowing depended on an external, non-Terraform-managed process. The
# security group's Terraform-declared state is now the actual, complete restriction — not a
# permissive baseline some other system is trusted to tighten after the fact.
resource "aws_vpc_security_group_ingress_rule" "nlb_https" {
  for_each = var.create_eks_topology_security_groups ? toset(var.nlb_allowed_cidrs) : toset([])

  security_group_id = aws_security_group.nlb[0].id
  description       = "HTTPS from Cloudflare published edge range ${each.value} (ADR-004 - Cloudflare is the sole public edge, this NLB its only origin)."
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "nlb_to_eks_nodes" {
  count = var.create_eks_topology_security_groups ? 1 : 0

  security_group_id            = aws_security_group.nlb[0].id
  description                  = "To EKS worker nodes only - the NLB has no other reason to originate traffic."
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.eks_nodes[0].id
}

resource "aws_security_group" "eks_nodes" {
  count = var.create_eks_topology_security_groups ? 1 : 0

  name_prefix = "${var.name_prefix}-eks-node-"
  description = "EKS worker nodes - created now, attached to the node group in Phase 3."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-eks-node-sg"
    Application = "networking"
    Purpose     = "eks-node-security-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "eks_nodes_from_nlb" {
  count = var.create_eks_topology_security_groups ? 1 : 0

  security_group_id            = aws_security_group.eks_nodes[0].id
  description                  = "From the NLB - NGINX Ingress Controller NodePort range."
  ip_protocol                  = "tcp"
  from_port                    = 30000
  to_port                      = 32767
  referenced_security_group_id = aws_security_group.nlb[0].id
}

resource "aws_vpc_security_group_ingress_rule" "eks_nodes_self" {
  count = var.create_eks_topology_security_groups ? 1 : 0

  security_group_id            = aws_security_group.eks_nodes[0].id
  description                  = "Node-to-node - required for the CNI (pod networking) and control-plane-to-kubelet communication."
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.eks_nodes[0].id
}

resource "aws_vpc_security_group_egress_rule" "eks_nodes_to_aurora" {
  count = var.create_eks_topology_security_groups ? 1 : 0

  security_group_id            = aws_security_group.eks_nodes[0].id
  description                  = "To Aurora - Postgres."
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.aurora.id
}

resource "aws_vpc_security_group_egress_rule" "eks_nodes_to_redis" {
  count = var.create_eks_topology_security_groups ? 1 : 0

  security_group_id            = aws_security_group.eks_nodes[0].id
  description                  = "To ElastiCache - Redis."
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = aws_security_group.redis[0].id
}

resource "aws_vpc_security_group_egress_rule" "eks_nodes_https_internet" {
  count = var.create_eks_topology_security_groups ? 1 : 0

  security_group_id = aws_security_group.eks_nodes[0].id
  description       = "HTTPS to the internet (via NAT) - Cloudinary, Razorpay, ECR, SMTP provider (cloud-architecture-blueprint.md Section 2)."
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "aurora" {
  name_prefix = "${var.name_prefix}-aurora-"
  description = "Aurora PostgreSQL - created now, attached to the cluster in Phase 4."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-aurora-sg"
    Application = "networking"
    Purpose     = "aurora-security-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "aurora_from_eks_nodes" {
  count = var.create_eks_topology_security_groups ? 1 : 0

  security_group_id            = aws_security_group.aurora.id
  description                  = "Postgres from EKS worker nodes only - no other ingress path exists."
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.eks_nodes[0].id
}

resource "aws_security_group" "redis" {
  count = var.create_eks_topology_security_groups ? 1 : 0

  name_prefix = "${var.name_prefix}-redis-"
  description = "ElastiCache Redis - created now, attached to the cluster in Phase 4."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-redis-sg"
    Application = "networking"
    Purpose     = "redis-security-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "redis_from_eks_nodes" {
  count = var.create_eks_topology_security_groups ? 1 : 0

  security_group_id            = aws_security_group.redis[0].id
  description                  = "Redis from EKS worker nodes only - no other ingress path exists."
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = aws_security_group.eks_nodes[0].id
}

# Address moves for the count gating above — every caller that keeps the default
# (create_eks_topology_security_groups = true) sees a pure state move, not a destroy/create.
moved {
  from = aws_security_group.nlb
  to   = aws_security_group.nlb[0]
}

moved {
  from = aws_vpc_security_group_egress_rule.nlb_to_eks_nodes
  to   = aws_vpc_security_group_egress_rule.nlb_to_eks_nodes[0]
}

moved {
  from = aws_security_group.eks_nodes
  to   = aws_security_group.eks_nodes[0]
}

moved {
  from = aws_vpc_security_group_ingress_rule.eks_nodes_from_nlb
  to   = aws_vpc_security_group_ingress_rule.eks_nodes_from_nlb[0]
}

moved {
  from = aws_vpc_security_group_ingress_rule.eks_nodes_self
  to   = aws_vpc_security_group_ingress_rule.eks_nodes_self[0]
}

moved {
  from = aws_vpc_security_group_egress_rule.eks_nodes_to_aurora
  to   = aws_vpc_security_group_egress_rule.eks_nodes_to_aurora[0]
}

moved {
  from = aws_vpc_security_group_egress_rule.eks_nodes_to_redis
  to   = aws_vpc_security_group_egress_rule.eks_nodes_to_redis[0]
}

moved {
  from = aws_vpc_security_group_egress_rule.eks_nodes_https_internet
  to   = aws_vpc_security_group_egress_rule.eks_nodes_https_internet[0]
}

moved {
  from = aws_vpc_security_group_ingress_rule.aurora_from_eks_nodes
  to   = aws_vpc_security_group_ingress_rule.aurora_from_eks_nodes[0]
}

moved {
  from = aws_security_group.redis
  to   = aws_security_group.redis[0]
}

moved {
  from = aws_vpc_security_group_ingress_rule.redis_from_eks_nodes
  to   = aws_vpc_security_group_ingress_rule.redis_from_eks_nodes[0]
}

# --- ECS/ALB topology ------------------------------------------------------------------------------
# Gated behind var.create_ecs_topology_security_groups (default false). Originally added for the
# temporary DEV+QA environment (environments/development-temp, standalone RDS); Production's ECS
# Fargate runtime uses the same groups with var.ecs_database_target = "aurora", which swaps the
# standalone-RDS group for the RDS Proxy + migration-task groups further below.

locals {
  ecs_topology             = var.create_ecs_topology_security_groups
  ecs_uses_rds             = local.ecs_topology && var.ecs_database_target == "rds"
  ecs_uses_aurora          = local.ecs_topology && var.ecs_database_target == "aurora"
  alb_http_ingress         = local.ecs_topology && var.alb_http_redirect_ingress
  alb_cidrs_are_cloudflare = !contains(var.alb_allowed_cidrs, "0.0.0.0/0")
}

resource "aws_security_group" "alb" {
  count = local.ecs_topology ? 1 : 0

  name_prefix = "${var.name_prefix}-alb-"
  description = "ALB - the internet-facing entry point for the ECS-fronted (non-EKS) topology."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-alb-sg"
    Application = "networking"
    Purpose     = "alb-security-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# One rule per allowed CIDR (var.alb_allowed_cidrs) — Cloudflare's published ranges where Cloudflare
# fronts the ALB (development-temp), or 0.0.0.0/0 where the ALB itself is the public, AWS
# WAF-protected edge (Production, ADR-004 as amended). The description reflects which case applies.
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  for_each = local.ecs_topology ? toset(var.alb_allowed_cidrs) : toset([])

  security_group_id = aws_security_group.alb[0].id
  description = (
    local.alb_cidrs_are_cloudflare
    ? "HTTPS from Cloudflare published edge range ${each.value} (Cloudflare is the sole public edge; this ALB is its only origin)."
    : "HTTPS from ${each.value} - public ALB, AWS WAF-protected (ADR-004 as amended)."
  )
  ip_protocol = "tcp"
  from_port   = 443
  to_port     = 443
  cidr_ipv4   = each.value
}

# Port 80 exists only so modules/alb's HTTP -> HTTPS redirect listener is reachable; nothing is
# ever served over plain HTTP.
resource "aws_vpc_security_group_ingress_rule" "alb_http_redirect" {
  for_each = local.alb_http_ingress ? toset(var.alb_allowed_cidrs) : toset([])

  security_group_id = aws_security_group.alb[0].id
  description       = "HTTP from ${each.value} - redirect-to-HTTPS listener only, never served."
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ecs_tasks" {
  count = local.ecs_topology ? 1 : 0

  security_group_id            = aws_security_group.alb[0].id
  description                  = "To ECS API tasks only - the ALB has no other reason to originate traffic."
  ip_protocol                  = "tcp"
  from_port                    = var.ecs_api_container_port
  to_port                      = var.ecs_api_container_port
  referenced_security_group_id = aws_security_group.ecs_tasks[0].id
}

resource "aws_security_group" "ecs_tasks" {
  count = local.ecs_topology ? 1 : 0

  name_prefix = "${var.name_prefix}-ecs-task-"
  description = "ECS Fargate tasks (API + worker) - the ECS-fronted counterpart to the eks_nodes security group above."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-ecs-task-sg"
    Application = "networking"
    Purpose     = "ecs-task-security-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "ecs_tasks_from_alb" {
  count = local.ecs_topology ? 1 : 0

  security_group_id            = aws_security_group.ecs_tasks[0].id
  description                  = "From the ALB - the API container listening port. The worker task has no ALB target and receives no ingress here at all."
  ip_protocol                  = "tcp"
  from_port                    = var.ecs_api_container_port
  to_port                      = var.ecs_api_container_port
  referenced_security_group_id = aws_security_group.alb[0].id
}

resource "aws_vpc_security_group_egress_rule" "ecs_tasks_to_rds" {
  count = local.ecs_uses_rds ? 1 : 0

  security_group_id            = aws_security_group.ecs_tasks[0].id
  description                  = "To RDS PostgreSQL."
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.rds[0].id
}

resource "aws_vpc_security_group_egress_rule" "ecs_tasks_to_redis" {
  count = local.ecs_topology ? 1 : 0

  security_group_id            = aws_security_group.ecs_tasks[0].id
  description                  = "To ElastiCache Redis."
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = aws_security_group.redis_ecs[0].id
}

resource "aws_vpc_security_group_egress_rule" "ecs_tasks_https_internet" {
  count = local.ecs_topology ? 1 : 0

  security_group_id = aws_security_group.ecs_tasks[0].id
  description       = "HTTPS to the internet (via NAT) - Cloudinary, Razorpay, ECR, SMTP provider."
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "rds" {
  count = local.ecs_uses_rds ? 1 : 0

  name_prefix = "${var.name_prefix}-rds-"
  description = "Standalone RDS PostgreSQL (modules/rds) - the ECS-fronted counterpart to the aurora security group above. Not used by, and does not affect, any Aurora cluster."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-rds-sg"
    Application = "networking"
    Purpose     = "rds-security-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_ecs_tasks" {
  count = local.ecs_uses_rds ? 1 : 0

  security_group_id            = aws_security_group.rds[0].id
  description                  = "Postgres from ECS tasks only - no other ingress path exists."
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.ecs_tasks[0].id
}

resource "aws_security_group" "redis_ecs" {
  count = local.ecs_topology ? 1 : 0

  name_prefix = "${var.name_prefix}-redis-ecs-"
  description = "ElastiCache Redis (cluster mode disabled, modules/elasticache) for the ECS-fronted topology - the counterpart to the redis security group above. Not shared with any EKS-fronted Redis."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-redis-ecs-sg"
    Application = "networking"
    Purpose     = "redis-ecs-security-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "redis_ecs_from_ecs_tasks" {
  count = local.ecs_topology ? 1 : 0

  security_group_id            = aws_security_group.redis_ecs[0].id
  description                  = "Redis from ECS tasks only - no other ingress path exists."
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = aws_security_group.ecs_tasks[0].id
}

# --- ECS -> Aurora (var.ecs_database_target = "aurora") -------------------------------------------
# Two distinct database paths, each with its own security group, so network policy matches the
# credential split (docs/production-database-bootstrap.md):
#
#   API/worker tasks (ecs_tasks)   -> RDS Proxy (rds_proxy) -> Aurora   runtime app user, pooled
#   migration task (ecs_migration) -> Aurora writer directly            migrator user, DDL
#
# API/worker tasks have NO direct route to Aurora — only through the proxy. The migration task is
# launched by CI with `aws ecs run-task --network-configuration` naming ecs_migration explicitly;
# it receives no ingress and reaches nothing but Aurora and HTTPS (ECR, Secrets Manager, Logs).

resource "aws_security_group" "rds_proxy" {
  count = local.ecs_uses_aurora ? 1 : 0

  name_prefix = "${var.name_prefix}-rds-proxy-"
  description = "RDS Proxy in front of Aurora PostgreSQL - the only database endpoint ECS API/worker tasks can reach."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-rds-proxy-sg"
    Application = "networking"
    Purpose     = "rds-proxy-security-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "ecs_tasks_to_rds_proxy" {
  count = local.ecs_uses_aurora ? 1 : 0

  security_group_id            = aws_security_group.ecs_tasks[0].id
  description                  = "To RDS Proxy (Postgres) - the only database path for API/worker tasks."
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.rds_proxy[0].id
}

resource "aws_vpc_security_group_ingress_rule" "rds_proxy_from_ecs_tasks" {
  count = local.ecs_uses_aurora ? 1 : 0

  security_group_id            = aws_security_group.rds_proxy[0].id
  description                  = "Postgres from ECS API/worker tasks only."
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.ecs_tasks[0].id
}

resource "aws_vpc_security_group_egress_rule" "rds_proxy_to_aurora" {
  count = local.ecs_uses_aurora ? 1 : 0

  security_group_id            = aws_security_group.rds_proxy[0].id
  description                  = "To Aurora PostgreSQL - pooled backend connections from RDS Proxy."
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.aurora.id
}

resource "aws_vpc_security_group_ingress_rule" "aurora_from_rds_proxy" {
  count = local.ecs_uses_aurora ? 1 : 0

  security_group_id            = aws_security_group.aurora.id
  description                  = "Postgres from RDS Proxy - the runtime application path."
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.rds_proxy[0].id
}

resource "aws_security_group" "ecs_migration" {
  count = local.ecs_uses_aurora ? 1 : 0

  name_prefix = "${var.name_prefix}-ecs-migration-"
  description = "One-off ECS migration task (prisma migrate deploy) - direct Aurora writer access with migrator credentials, no ingress."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-ecs-migration-sg"
    Application = "networking"
    Purpose     = "ecs-migration-security-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "ecs_migration_to_aurora" {
  count = local.ecs_uses_aurora ? 1 : 0

  security_group_id            = aws_security_group.ecs_migration[0].id
  description                  = "To the Aurora writer - Prisma migrations bypass RDS Proxy (session-level advisory locks)."
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.aurora.id
}

resource "aws_vpc_security_group_egress_rule" "ecs_migration_https_internet" {
  count = local.ecs_uses_aurora ? 1 : 0

  security_group_id = aws_security_group.ecs_migration[0].id
  description       = "HTTPS (via NAT) - ECR image pull, Secrets Manager, CloudWatch Logs."
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "aurora_from_ecs_migration" {
  count = local.ecs_uses_aurora ? 1 : 0

  security_group_id            = aws_security_group.aurora.id
  description                  = "Postgres from the one-off ECS migration task - schema changes only."
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.ecs_migration[0].id
}
