# Amazon RDS Proxy in front of an Aurora PostgreSQL cluster — the ECS-era replacement for the
# in-cluster PgBouncer the EKS design used (modules/eks-addons/pgbouncer.tf). It pools the many
# short-lived Prisma connection pools of every API/worker task into a bounded set of backend
# connections, and absorbs Aurora writer failover without each task having to rediscover the
# writer.
#
# Authentication is Secrets-Manager-based: the proxy reads the application user's
# {username, password} JSON secret (var.auth_secret_arn) and accepts only that user. TLS is
# required on the client side (require_tls) and Aurora already enforces rds.force_ssl=1 on the
# backend side (modules/aurora).

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = "${var.name_prefix}-rds-proxy-role"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  permissions_boundary = var.permission_boundary_arn

  tags = merge(var.tags, { Application = "rds-proxy", Purpose = "rds-proxy-secret-access-role" })
}

# Exactly the one credential secret the proxy authenticates with, decrypted only via Secrets
# Manager — the proxy can read nothing else.
data "aws_iam_policy_document" "secret_access" {
  statement {
    sid       = "ReadProxyAuthSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.auth_secret_arn]
  }

  statement {
    sid       = "DecryptProxyAuthSecret"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [var.secrets_kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${data.aws_region.current.name}.amazonaws.com"]
    }
  }
}

data "aws_region" "current" {}

resource "aws_iam_role_policy" "secret_access" {
  name   = "${var.name_prefix}-rds-proxy-secret-access"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.secret_access.json
}

resource "aws_db_proxy" "this" {
  name                   = "${var.name_prefix}-aurora-proxy"
  engine_family          = "POSTGRESQL"
  role_arn               = aws_iam_role.this.arn
  vpc_subnet_ids         = var.subnet_ids
  vpc_security_group_ids = [var.security_group_id]
  require_tls            = true
  idle_client_timeout    = var.idle_client_timeout_seconds
  debug_logging          = false # would log SQL statements, including parameter values

  auth {
    auth_scheme               = "SECRETS"
    iam_auth                  = "DISABLED"
    client_password_auth_type = "POSTGRES_SCRAM_SHA_256"
    secret_arn                = var.auth_secret_arn
    description               = "Runtime application database user"
  }

  tags = merge(var.tags, { Application = "rds-proxy", Purpose = "aurora-connection-pool" })

  depends_on = [aws_iam_role_policy.secret_access]
}

resource "aws_db_proxy_default_target_group" "this" {
  db_proxy_name = aws_db_proxy.this.name

  connection_pool_config {
    # Leaves (100 - max_connections_percent)% of Aurora's max_connections for the direct paths
    # that bypass the proxy: the migration task and operator sessions.
    max_connections_percent      = var.max_connections_percent
    max_idle_connections_percent = var.max_idle_connections_percent
    connection_borrow_timeout    = var.connection_borrow_timeout_seconds
  }
}

resource "aws_db_proxy_target" "this" {
  db_proxy_name         = aws_db_proxy.this.name
  target_group_name     = aws_db_proxy_default_target_group.this.name
  db_cluster_identifier = var.db_cluster_identifier
}
