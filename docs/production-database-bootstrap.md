# Production database bootstrap — application and migration roles

**Run once, ever**, after `environments/production/data` is first applied and before the first
`backend-deploy-ecs.yml` run. Re-running is unnecessary; the statements are not idempotent by
design (a second run fails loudly on `CREATE ROLE` instead of silently changing grants).

## Why this is not Terraform

`environments/production/data/database-access.tf` generates the two passwords and stores every
credential and `DATABASE_URL` in Secrets Manager, but it does not create the PostgreSQL roles:
that needs the RDS-managed **master** credential (rotated by RDS, never a Terraform value) and a SQL
session from inside the private-data network. A Terraform PostgreSQL provider would need both
in Terraform's own execution context and state, so this is a documented manual step instead.

## The identities

| Role | Used by | Connects to | Rights |
|---|---|---|---|
| `patheya_admin` (RDS-managed master) | this bootstrap only | Aurora writer | `rds_superuser` |
| `patheya_migrator` | ECS migration task (`prisma migrate deploy`) | Aurora writer, directly | owns the database and `public` schema (DDL, `CREATE EXTENSION pg_trgm`) |
| `patheya_app` | ECS API + worker tasks | **RDS Proxy** only | `SELECT/INSERT/UPDATE/DELETE` on tables, sequence usage, function execute — no DDL |

Secrets (all `patheya-express/production/*`, KMS key = data layer `secrets`):

| Secret | Shape | Consumer |
|---|---|---|
| `database-app-credentials` | `{"username":"patheya_app","password":...}` | RDS Proxy auth |
| `database-url` | `postgresql://patheya_app:...@<proxy>:5432/patheya_express?sslmode=require` | API/worker `DATABASE_URL` |
| `database-migrator-credentials` | `{"username":"patheya_migrator","password":...}` | this bootstrap |
| `database-migration-url` | `postgresql://patheya_migrator:...@<writer>:5432/patheya_express?sslmode=require` | migration task `DATABASE_URL` |

## Prerequisites

- Root layer in `build` or `live` (NAT Gateways up — the session below installs `psql` and calls
  Secrets Manager through NAT).
- Data layer applied. RDS Proxy shows its target as unavailable until step 4 — expected.
- You are signed in to account `512297269884` as `PlatformAdministrator` in `ap-south-1`.

## Procedure

1. **Open an AWS CloudShell VPC environment** (CloudShell → Actions → *Create VPC environment*):
   VPC `patheya-production-vpc`, one **private-app** subnet, security group
   **`patheya-production-ecs-migration-*`**. That group is the only one besides RDS Proxy that
   Aurora admits, and it has egress only to Aurora (5432) and HTTPS — no ingress at all.

2. **Install the client and load credentials into the shell** (never echo them):

   ```bash
   sudo dnf install -y postgresql16 jq
   curl -sSo /tmp/rds-ca.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

   # Values from `terraform output` in environments/production/data:
   MASTER_SECRET_ARN='<data output aurora_master_secret_arn>'
   export PGHOST='<data output aurora_writer_endpoint>'
   export PGDATABASE='patheya_express' PGSSLMODE='verify-full' PGSSLROOTCERT=/tmp/rds-ca.pem

   master_json="$(aws secretsmanager get-secret-value --secret-id "$MASTER_SECRET_ARN" --query SecretString --output text)"
   export PGUSER="$(jq -r .username <<<"$master_json")" PGPASSWORD="$(jq -r .password <<<"$master_json")"
   unset master_json

   APP_PW="$(aws secretsmanager get-secret-value --secret-id patheya-express/production/database-app-credentials --query SecretString --output text | jq -r .password)"
   MIG_PW="$(aws secretsmanager get-secret-value --secret-id patheya-express/production/database-migrator-credentials --query SecretString --output text | jq -r .password)"
   ```

3. **Create the roles and grants** (psql `:'var'` quoting keeps the passwords out of the command
   line and correctly quoted):

   ```bash
   psql -v ON_ERROR_STOP=1 -v app_pw="$APP_PW" -v mig_pw="$MIG_PW" <<'SQL'
   CREATE ROLE patheya_migrator LOGIN PASSWORD :'mig_pw';
   CREATE ROLE patheya_app      LOGIN PASSWORD :'app_pw';

   -- The migrator owns the database, and therefore (PostgreSQL 15+, pg_database_owner) the public
   -- schema: it can run DDL and CREATE EXTENSION pg_trgm (a trusted extension).
   ALTER DATABASE patheya_express OWNER TO patheya_migrator;
   REVOKE ALL ON DATABASE patheya_express FROM PUBLIC;
   GRANT CONNECT, TEMPORARY ON DATABASE patheya_express TO patheya_app;

   REVOKE CREATE ON SCHEMA public FROM PUBLIC;
   GRANT USAGE ON SCHEMA public TO patheya_app;

   -- Every object the migrator creates from now on is usable — never alterable — by the app.
   -- PostgreSQL 16 requires membership in the target role for ALTER DEFAULT PRIVILEGES FOR ROLE;
   -- the master holds it only for the duration of these statements.
   GRANT patheya_migrator TO CURRENT_USER;
   ALTER DEFAULT PRIVILEGES FOR ROLE patheya_migrator IN SCHEMA public
     GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO patheya_app;
   ALTER DEFAULT PRIVILEGES FOR ROLE patheya_migrator IN SCHEMA public
     GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO patheya_app;
   ALTER DEFAULT PRIVILEGES FOR ROLE patheya_migrator IN SCHEMA public
     GRANT EXECUTE ON FUNCTIONS TO patheya_app;
   REVOKE patheya_migrator FROM CURRENT_USER;
   SQL
   ```

4. **Verify**, then clean up:

   ```bash
   psql -At -c "select rolname from pg_roles where rolname in ('patheya_app','patheya_migrator') order by 1"
   aws rds describe-db-proxy-targets --db-proxy-name patheya-production-aurora-proxy \
     --query 'Targets[].TargetHealth.State'      # expect AVAILABLE (may take ~1-2 minutes)
   unset PGPASSWORD APP_PW MIG_PW
   ```

   Delete the CloudShell VPC environment afterwards — it is not a standing access path.

5. The first `backend-deploy-ecs.yml` run then applies every Prisma migration as
   `patheya_migrator` before the services start.

## Password rotation (manual, planned maintenance)

1. `terraform apply -replace=random_password.app_db` (or `migrator_db`) in `production/data` — the
   credential and URL secrets update together.
2. `ALTER ROLE patheya_app PASSWORD '<new>'` through the same CloudShell procedure.
3. Run `backend-deploy-ecs.yml` for the currently deployed tag (or force a new deployment) so tasks
   pick up the new `DATABASE_URL`; RDS Proxy re-reads its secret on its own.

## Other Production secrets (populated out-of-band, never by Terraform)

Values are written with `aws secretsmanager put-secret-value`; shapes match the ECS task
definition's JSON-key references (environments/production/app/main.tf):

| Secret | Shape |
|---|---|
| `jwt-signing-key` | `{"accessSecret","refreshSecret"}` — ≥ 32 chars each, different |
| `cloudinary` | `{"cloudName","apiKey","apiSecret"}` |
| `razorpay` | `{"keyId" (rzp_live_...),"keySecret","webhookSecret"}` |
| `smtp` | `{"host","port","user","pass","from"}` |
| `bank-account-encryption-key` | plain string (≥ 20 chars) — required at boot in production |
| `super-admin-bootstrap` | `{"email","password","firstName","lastName","phone"}` |

`redis-auth-token` and the four database secrets above are generated by Terraform.
