# The four Security Groups from cloud-architecture-blueprint.md Section 2's table, created now as
# the networking foundation even though nothing attaches to eks-node-sg/aurora-sg/redis-sg until
# Phase 3/4 — a Security Group is a free, VPC-scoped ACL object with no resource behind it yet to
# provision ahead of need; unlike a KMS key (modules/kms) or an actual EKS/Aurora/Redis resource,
# there's no idle-cost or premature-commitment argument against defining the network policy now so
# later phases attach to an already-reviewed boundary instead of inventing one under deploy pressure.

resource "aws_security_group" "nlb" {
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
  for_each = toset(var.nlb_allowed_cidrs)

  security_group_id = aws_security_group.nlb.id
  description       = "HTTPS from Cloudflare published edge range ${each.value} (ADR-004 - Cloudflare is the sole public edge, this NLB its only origin)."
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "nlb_to_eks_nodes" {
  security_group_id            = aws_security_group.nlb.id
  description                  = "To EKS worker nodes only - the NLB has no other reason to originate traffic."
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.eks_nodes.id
}

resource "aws_security_group" "eks_nodes" {
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
  security_group_id            = aws_security_group.eks_nodes.id
  description                  = "From the NLB - NGINX Ingress Controller NodePort range."
  ip_protocol                  = "tcp"
  from_port                    = 30000
  to_port                      = 32767
  referenced_security_group_id = aws_security_group.nlb.id
}

resource "aws_vpc_security_group_ingress_rule" "eks_nodes_self" {
  security_group_id            = aws_security_group.eks_nodes.id
  description                  = "Node-to-node - required for the CNI (pod networking) and control-plane-to-kubelet communication."
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.eks_nodes.id
}

resource "aws_vpc_security_group_egress_rule" "eks_nodes_to_aurora" {
  security_group_id            = aws_security_group.eks_nodes.id
  description                  = "To Aurora - Postgres."
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.aurora.id
}

resource "aws_vpc_security_group_egress_rule" "eks_nodes_to_redis" {
  security_group_id            = aws_security_group.eks_nodes.id
  description                  = "To ElastiCache - Redis."
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = aws_security_group.redis.id
}

resource "aws_vpc_security_group_egress_rule" "eks_nodes_https_internet" {
  security_group_id = aws_security_group.eks_nodes.id
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
  security_group_id            = aws_security_group.aurora.id
  description                  = "Postgres from EKS worker nodes only - no other ingress path exists."
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.eks_nodes.id
}

resource "aws_security_group" "redis" {
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
  security_group_id            = aws_security_group.redis.id
  description                  = "Redis from EKS worker nodes only - no other ingress path exists."
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = aws_security_group.eks_nodes.id
}

# --- ECS/ALB topology (Phase 2, temporary DEV+QA) -----------------------------------------------
# Everything below is purely additive and gated behind var.create_ecs_topology_security_groups
# (default false) — nothing above this point is modified, referenced, or replaced. This is a
# parallel security-group set for an ECS Fargate-fronted environment with no EKS nodes at all
# (environments/development-temp); the EKS-oriented resources above remain exactly as they were
# for every environment that still uses them.

resource "aws_security_group" "alb" {
  count = var.create_ecs_topology_security_groups ? 1 : 0

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

# Cloudflare-only ingress — one rule per published Cloudflare CIDR (var.alb_allowed_cidrs), never
# 0.0.0.0/0, matching the nlb_https rule's exact rationale above.
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  for_each = var.create_ecs_topology_security_groups ? toset(var.alb_allowed_cidrs) : toset([])

  security_group_id = aws_security_group.alb[0].id
  description       = "HTTPS from Cloudflare published edge range ${each.value} (Cloudflare is the sole public edge; this ALB is its only origin)."
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "alb_to_ecs_tasks" {
  count = var.create_ecs_topology_security_groups ? 1 : 0

  security_group_id            = aws_security_group.alb[0].id
  description                  = "To ECS API tasks only - the ALB has no other reason to originate traffic."
  ip_protocol                  = "tcp"
  from_port                    = var.ecs_api_container_port
  to_port                      = var.ecs_api_container_port
  referenced_security_group_id = aws_security_group.ecs_tasks[0].id
}

resource "aws_security_group" "ecs_tasks" {
  count = var.create_ecs_topology_security_groups ? 1 : 0

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
  count = var.create_ecs_topology_security_groups ? 1 : 0

  security_group_id            = aws_security_group.ecs_tasks[0].id
  description                  = "From the ALB - the API container listening port. The worker task has no ALB target and receives no ingress here at all."
  ip_protocol                  = "tcp"
  from_port                    = var.ecs_api_container_port
  to_port                      = var.ecs_api_container_port
  referenced_security_group_id = aws_security_group.alb[0].id
}

resource "aws_vpc_security_group_egress_rule" "ecs_tasks_to_rds" {
  count = var.create_ecs_topology_security_groups ? 1 : 0

  security_group_id            = aws_security_group.ecs_tasks[0].id
  description                  = "To RDS PostgreSQL."
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.rds[0].id
}

resource "aws_vpc_security_group_egress_rule" "ecs_tasks_to_redis" {
  count = var.create_ecs_topology_security_groups ? 1 : 0

  security_group_id            = aws_security_group.ecs_tasks[0].id
  description                  = "To ElastiCache Redis."
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = aws_security_group.redis_ecs[0].id
}

resource "aws_vpc_security_group_egress_rule" "ecs_tasks_https_internet" {
  count = var.create_ecs_topology_security_groups ? 1 : 0

  security_group_id = aws_security_group.ecs_tasks[0].id
  description       = "HTTPS to the internet (via NAT) - Cloudinary, Razorpay, ECR, SMTP provider."
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "rds" {
  count = var.create_ecs_topology_security_groups ? 1 : 0

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
  count = var.create_ecs_topology_security_groups ? 1 : 0

  security_group_id            = aws_security_group.rds[0].id
  description                  = "Postgres from ECS tasks only - no other ingress path exists."
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.ecs_tasks[0].id
}

resource "aws_security_group" "redis_ecs" {
  count = var.create_ecs_topology_security_groups ? 1 : 0

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
  count = var.create_ecs_topology_security_groups ? 1 : 0

  security_group_id            = aws_security_group.redis_ecs[0].id
  description                  = "Redis from ECS tasks only - no other ingress path exists."
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = aws_security_group.ecs_tasks[0].id
}
