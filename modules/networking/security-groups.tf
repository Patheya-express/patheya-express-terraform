# The four Security Groups from cloud-architecture-blueprint.md Section 2's table, created now as
# the networking foundation even though nothing attaches to eks-node-sg/aurora-sg/redis-sg until
# Phase 3/4 — a Security Group is a free, VPC-scoped ACL object with no resource behind it yet to
# provision ahead of need; unlike a KMS key (modules/kms) or an actual EKS/Aurora/Redis resource,
# there's no idle-cost or premature-commitment argument against defining the network policy now so
# later phases attach to an already-reviewed boundary instead of inventing one under deploy pressure.

resource "aws_security_group" "nlb" {
  name_prefix = "${var.name_prefix}-nlb-"
  description = "AWS NLB — the single internet-facing entry point (cloud-architecture-blueprint.md Section 1)."
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

resource "aws_vpc_security_group_ingress_rule" "nlb_https" {
  security_group_id = aws_security_group.nlb.id
  description       = "HTTPS from Cloudflare's edge only in practice — CIDR list synced by a scheduled process outside this module (cloud-architecture-blueprint.md Section 2 footnote); 0.0.0.0/0 here is the Terraform-expressible baseline, narrowed operationally."
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "nlb_to_eks_nodes" {
  security_group_id            = aws_security_group.nlb.id
  description                  = "To EKS worker nodes only — the NLB has no other reason to originate traffic."
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.eks_nodes.id
}

resource "aws_security_group" "eks_nodes" {
  name_prefix = "${var.name_prefix}-eks-node-"
  description = "EKS worker nodes — created now, attached to the node group in Phase 3."
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
  description                  = "From the NLB — NGINX Ingress Controller's NodePort range."
  ip_protocol                  = "tcp"
  from_port                    = 30000
  to_port                      = 32767
  referenced_security_group_id = aws_security_group.nlb.id
}

resource "aws_vpc_security_group_ingress_rule" "eks_nodes_self" {
  security_group_id            = aws_security_group.eks_nodes.id
  description                  = "Node-to-node — required for the CNI (pod networking) and control-plane-to-kubelet communication."
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.eks_nodes.id
}

resource "aws_vpc_security_group_egress_rule" "eks_nodes_to_aurora" {
  security_group_id            = aws_security_group.eks_nodes.id
  description                  = "To Aurora — Postgres."
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.aurora.id
}

resource "aws_vpc_security_group_egress_rule" "eks_nodes_to_redis" {
  security_group_id            = aws_security_group.eks_nodes.id
  description                  = "To ElastiCache — Redis."
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = aws_security_group.redis.id
}

resource "aws_vpc_security_group_egress_rule" "eks_nodes_https_internet" {
  security_group_id = aws_security_group.eks_nodes.id
  description       = "HTTPS to the internet (via NAT) — Cloudinary, Razorpay, ECR, SMTP provider (cloud-architecture-blueprint.md Section 2)."
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "aurora" {
  name_prefix = "${var.name_prefix}-aurora-"
  description = "Aurora PostgreSQL — created now, attached to the cluster in Phase 4."
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
  description                  = "Postgres from EKS worker nodes only — no other ingress path exists."
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.eks_nodes.id
}

resource "aws_security_group" "redis" {
  name_prefix = "${var.name_prefix}-redis-"
  description = "ElastiCache Redis — created now, attached to the cluster in Phase 4."
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
  description                  = "Redis from EKS worker nodes only — no other ingress path exists."
  ip_protocol                  = "tcp"
  from_port                    = 6379
  to_port                      = 6379
  referenced_security_group_id = aws_security_group.eks_nodes.id
}
