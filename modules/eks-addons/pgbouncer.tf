# PgBouncer (this task's Section 2) — transaction-pooling connection pooler sitting between
# every Prisma client and Aurora, per cloud-architecture-blueprint.md Section 5: "Necessary:
# Prisma's own connection pool is per-pod-instance, and at api-gateway's HPA ceiling ... naive
# per-pod Postgres connections would approach Aurora's max_connections ceiling well before
# compute is actually the bottleneck." Two virtual databases (patheya_write/patheya_read) route
# to the writer/reader endpoints respectively — one Deployment, one Service, no separate pooler
# process per role.
#
# userlist.txt is rendered by an init container from the ExternalSecret-synced Aurora credential
# (external-secrets.tf's pgbouncer_credentials_external_secret) — never baked into the image or
# the ConfigMap, and never handled by this Terraform module in plaintext at apply time (Terraform
# only references the Secret by name; it never reads its value).

locals {
  pgbouncer_namespace = kubernetes_namespace_v1.data_platform["data-platform"].metadata[0].name
}

resource "kubernetes_config_map_v1" "pgbouncer_config" {
  metadata {
    name      = "pgbouncer-config"
    namespace = local.pgbouncer_namespace
  }

  data = {
    "pgbouncer.ini" = <<-EOT
      [databases]
      patheya_write = host=${var.aurora_writer_endpoint} port=${var.aurora_port} dbname=${var.aurora_database_name} sslmode=require
      patheya_read = host=${coalesce(var.aurora_reader_endpoint, var.aurora_writer_endpoint)} port=${var.aurora_port} dbname=${var.aurora_database_name} sslmode=require

      [pgbouncer]
      listen_addr = 0.0.0.0
      listen_port = 6432
      unix_socket_dir =
      auth_type = scram-sha-256
      auth_file = /etc/pgbouncer-generated/userlist.txt
      pool_mode = transaction
      max_client_conn = 2000
      default_pool_size = 25
      min_pool_size = 5
      reserve_pool_size = 10
      reserve_pool_timeout = 3
      server_tls_sslmode = require
      admin_users = pgbouncer_admin
      stats_users = pgbouncer_admin
      ignore_startup_parameters = extra_float_digits
      log_connections = 1
      log_disconnections = 1
    EOT
  }
}

resource "kubernetes_deployment_v1" "pgbouncer" {
  metadata {
    name      = "pgbouncer"
    namespace = local.pgbouncer_namespace
    labels = {
      "app.kubernetes.io/name"       = "pgbouncer"
      "app.kubernetes.io/component"  = "connection-pooler"
      "app.kubernetes.io/part-of"    = "patheya-express"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    replicas = var.pgbouncer_replica_count

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "pgbouncer"
      }
    }

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_unavailable = 0
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"       = "pgbouncer"
          "app.kubernetes.io/component"  = "connection-pooler"
          "app.kubernetes.io/part-of"    = "patheya-express"
          "app.kubernetes.io/managed-by" = "terraform"
        }
      }

      spec {
        priority_class_name             = "platform-critical"
        automount_service_account_token = false

        security_context {
          run_as_non_root = true
          run_as_user     = 1000
          fs_group        = 1000
        }

        affinity {
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              pod_affinity_term {
                label_selector {
                  match_expressions {
                    key      = "app.kubernetes.io/name"
                    operator = "In"
                    values   = ["pgbouncer"]
                  }
                }
                topology_key = "kubernetes.io/hostname"
              }
            }
          }
        }

        topology_spread_constraint {
          max_skew           = 1
          topology_key       = "topology.kubernetes.io/zone"
          when_unsatisfiable = "ScheduleAnyway"
          label_selector {
            match_labels = {
              "app.kubernetes.io/name" = "pgbouncer"
            }
          }
        }

        init_container {
          name  = "render-userlist"
          image = "busybox:1.36"

          command = [
            "sh", "-c",
            "printf '\"%s\" \"%s\"\\n\"pgbouncer_admin\" \"%s\"\\n' \"$DB_USERNAME\" \"$DB_PASSWORD\" \"$DB_PASSWORD\" > /etc/pgbouncer-generated/userlist.txt && chmod 0600 /etc/pgbouncer-generated/userlist.txt"
          ]

          env {
            name = "DB_USERNAME"
            value_from {
              secret_key_ref {
                name = "pgbouncer-credentials"
                key  = "username"
              }
            }
          }
          env {
            name = "DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = "pgbouncer-credentials"
                key  = "password"
              }
            }
          }

          security_context {
            run_as_non_root            = true
            run_as_user                = 1000
            read_only_root_filesystem  = true
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "generated"
            mount_path = "/etc/pgbouncer-generated"
          }
        }

        container {
          name  = "pgbouncer"
          image = "edoburu/pgbouncer:1.21.0"

          command = ["pgbouncer", "/etc/pgbouncer/pgbouncer.ini"]

          port {
            name           = "pgbouncer"
            container_port = 6432
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }

          security_context {
            run_as_non_root            = true
            run_as_user                = 1000
            read_only_root_filesystem  = true
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }

          liveness_probe {
            tcp_socket {
              port = 6432
            }
            initial_delay_seconds = 10
            period_seconds        = 15
            timeout_seconds       = 3
          }

          readiness_probe {
            tcp_socket {
              port = 6432
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 3
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/pgbouncer"
            read_only  = true
          }
          volume_mount {
            name       = "generated"
            mount_path = "/etc/pgbouncer-generated"
            read_only  = true
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }
        }

        # pgbouncer_exporter (this task's Section 2 — "Metrics endpoint") — no ServiceMonitor/
        # scrape config exists yet (Phase 5 installs Prometheus), the endpoint just exists,
        # exactly the "prepare, don't install the observability stack" scope this phase and
        # Phase 3 both hold to.
        container {
          name  = "pgbouncer-exporter"
          image = "prometheuscommunity/pgbouncer-exporter:v0.7.0"

          command = [
            "sh", "-c",
            "export DATA_SOURCE_NAME=\"postgres://pgbouncer_admin:${"$"}{DB_PASSWORD}@localhost:6432/pgbouncer?sslmode=disable\" && exec /pgbouncer_exporter"
          ]

          env {
            name = "DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = "pgbouncer-credentials"
                key  = "password"
              }
            }
          }

          port {
            name           = "metrics"
            container_port = 9127
          }

          resources {
            requests = {
              cpu    = "25m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "64Mi"
            }
          }

          security_context {
            run_as_non_root            = true
            run_as_user                = 1000
            read_only_root_filesystem  = true
            allow_privilege_escalation = false
            capabilities {
              drop = ["ALL"]
            }
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.pgbouncer_config.metadata[0].name
          }
        }
        volume {
          name = "generated"
          empty_dir {}
        }
        volume {
          name = "tmp"
          empty_dir {}
        }
      }
    }
  }

  depends_on = [kubernetes_manifest.pgbouncer_credentials_external_secret]
}

resource "kubernetes_service_v1" "pgbouncer" {
  metadata {
    name      = "pgbouncer"
    namespace = local.pgbouncer_namespace
    labels = {
      "app.kubernetes.io/name" = "pgbouncer"
    }
  }

  spec {
    type = "ClusterIP"
    selector = {
      "app.kubernetes.io/name" = "pgbouncer"
    }
    port {
      name        = "pgbouncer"
      port        = 6432
      target_port = 6432
    }
    port {
      name        = "metrics"
      port        = 9127
      target_port = 9127
    }
  }
}

resource "kubernetes_pod_disruption_budget_v1" "pgbouncer" {
  metadata {
    name      = "pgbouncer"
    namespace = local.pgbouncer_namespace
  }

  spec {
    min_available = var.pgbouncer_pdb_min_available
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "pgbouncer"
      }
    }
  }
}
