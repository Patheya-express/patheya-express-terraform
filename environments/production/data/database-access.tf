# Production database access — Aurora behind RDS Proxy, with separate runtime and migration
# identities (replaces the EKS design's External Secrets + PgBouncer DATABASE_URL templating).
#
#   API/worker tasks  DATABASE_URL = postgresql://patheya_app@<rds-proxy>/...       DML only
#   migration task    DATABASE_URL = postgresql://patheya_migrator@<aurora-writer>/... owns schema
#
# Terraform generates both passwords and stores every credential/URL in Secrets Manager under
# patheya-express/production/*, encrypted with this layer's `secrets` key. Nothing here is a
# Terraform output: ECS resolves the URL secrets at task launch, RDS Proxy reads the app user's
# credential secret itself.
#
# Terraform does NOT create the two PostgreSQL roles. That requires the RDS-managed master
# credential (rotated by RDS, never a Terraform value) and a SQL session inside the private-data
# network — a one-time privileged bootstrap documented step by step in
# docs/production-database-bootstrap.md. Until it is run, RDS Proxy reports its target as
# unavailable (AUTH_FAILURE) and the migration task cannot connect; nothing else is affected.
#
# Passwords are alphanumeric (no special characters) so they are URL-, shell- and
# SQL-literal-safe without encoding; 48 characters keeps entropy well above 256 bits.

locals {
  aurora_host          = module.aurora.writer_endpoint
  aurora_port          = module.aurora.port
  aurora_database_name = module.aurora.database_name
}

resource "random_password" "app_db" {
  length  = 48
  special = false
}

resource "random_password" "migrator_db" {
  length  = 48
  special = false
}

# --- Runtime application user (RDS Proxy auth + DATABASE_URL) ------------------------------------

resource "aws_secretsmanager_secret" "app_db_credentials" {
  name        = "patheya-express/production/database-app-credentials"
  description = "Runtime application PostgreSQL user (${var.app_db_username}) — RDS Proxy authenticates clients against this {username, password}. Role created by docs/production-database-bootstrap.md."
  kms_key_id  = module.kms.key_arns["secrets"]

  tags = merge(module.shared.tags, { Application = "secrets-manager", Purpose = "database-app-credentials" })
}

resource "aws_secretsmanager_secret_version" "app_db_credentials" {
  secret_id = aws_secretsmanager_secret.app_db_credentials.id
  secret_string = jsonencode({
    username = var.app_db_username
    password = random_password.app_db.result
  })
}

resource "aws_secretsmanager_secret" "database_url" {
  name        = "patheya-express/production/database-url"
  description = "Runtime DATABASE_URL for the ECS API/worker tasks — the application user through RDS Proxy, TLS required."
  kms_key_id  = module.kms.key_arns["secrets"]

  tags = merge(module.shared.tags, { Application = "secrets-manager", Purpose = "database-url-runtime" })
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id     = aws_secretsmanager_secret.database_url.id
  secret_string = "postgresql://${var.app_db_username}:${random_password.app_db.result}@${module.rds_proxy.endpoint}:${local.aurora_port}/${local.aurora_database_name}?sslmode=require"
}

# --- Migration user (direct to the Aurora writer) --------------------------------------------------
# Prisma Migrate takes session-level advisory locks, which RDS Proxy would pin for the whole
# session — and the migrator needs DDL rights the runtime user must never hold — so migrations
# connect to the writer endpoint directly, from the ecs_migration security group only.

resource "aws_secretsmanager_secret" "migrator_db_credentials" {
  name        = "patheya-express/production/database-migrator-credentials"
  description = "Schema-owning PostgreSQL user (${var.migrator_db_username}) for prisma migrate deploy. Role created by docs/production-database-bootstrap.md."
  kms_key_id  = module.kms.key_arns["secrets"]

  tags = merge(module.shared.tags, { Application = "secrets-manager", Purpose = "database-migrator-credentials" })
}

resource "aws_secretsmanager_secret_version" "migrator_db_credentials" {
  secret_id = aws_secretsmanager_secret.migrator_db_credentials.id
  secret_string = jsonencode({
    username = var.migrator_db_username
    password = random_password.migrator_db.result
  })
}

resource "aws_secretsmanager_secret" "database_migration_url" {
  name        = "patheya-express/production/database-migration-url"
  description = "DATABASE_URL for the one-off ECS migration task only — the migrator user, direct to the Aurora writer, TLS required."
  kms_key_id  = module.kms.key_arns["secrets"]

  tags = merge(module.shared.tags, { Application = "secrets-manager", Purpose = "database-url-migration" })
}

resource "aws_secretsmanager_secret_version" "database_migration_url" {
  secret_id     = aws_secretsmanager_secret.database_migration_url.id
  secret_string = "postgresql://${var.migrator_db_username}:${random_password.migrator_db.result}@${local.aurora_host}:${local.aurora_port}/${local.aurora_database_name}?sslmode=require"
}

# --- RDS service-linked role -------------------------------------------------------------------------
# RDS creates AWSServiceRoleForRDS implicitly only on the first DB cluster/instance creation, but
# CreateDBProxy requires it to already exist — so it is managed here, explicitly, and must exist
# before BOTH the Aurora cluster (otherwise RDS may create it implicitly first, and this resource's
# create then fails as already taken) and the proxy (the 2026-10-03 apply failed exactly so).
#
# The ordering is carried by referencing the role's plan-time-known service name from the one input
# each module uses ONLY on its not-yet-created resource (Aurora: the cluster's security group; RDS
# Proxy: the proxy's security group). A module-level depends_on is deliberately not used: it would
# defer each module's IAM policy-document data sources to apply time and show spurious in-place
# updates on the IAM roles/policies those modules already created.

resource "aws_iam_service_linked_role" "rds" {
  aws_service_name = "rds.amazonaws.com"
}

locals {
  rds_service_linked_role_ready = aws_iam_service_linked_role.rds.aws_service_name == "rds.amazonaws.com"

  # Values are unchanged; only the dependency on the service-linked role is added.
  aurora_cluster_security_group_id = local.rds_service_linked_role_ready ? data.terraform_remote_state.network.outputs.aurora_security_group_id : null
  rds_proxy_security_group_id      = local.rds_service_linked_role_ready ? data.terraform_remote_state.network.outputs.rds_proxy_security_group_id : null
}

# --- RDS Proxy ----------------------------------------------------------------------------------------

module "rds_proxy" {
  source = "../../../modules/rds-proxy"

  tags        = module.shared.tags
  name_prefix = module.shared.name_prefix

  db_cluster_identifier   = module.aurora.cluster_id
  subnet_ids              = data.terraform_remote_state.network.outputs.private_data_subnet_ids
  security_group_id       = local.rds_proxy_security_group_id
  auth_secret_arn         = aws_secretsmanager_secret.app_db_credentials.arn
  secrets_kms_key_arn     = module.kms.key_arns["secrets"]
  permission_boundary_arn = data.terraform_remote_state.network.outputs.permission_boundary_arn

  depends_on = [aws_secretsmanager_secret_version.app_db_credentials]
}
