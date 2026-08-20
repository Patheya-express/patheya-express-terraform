# 16 of this task's 17 named baseline policies (the 17th — signed images — is
# policies-image-verification.tf, kept separate because its enforcement mode is independently
# controlled: this phase's OBJECTIVE explicitly requires it at Enforce regardless of
# var.kyverno_policy_mode).
#
# Scope: patheya-backend/patheya-frontend ONLY, every policy, no exceptions. This is the single
# most important design decision in this file, so it's explained once, here, rather than
# repeated in every resource's comment:
#
# A cluster-wide "require non-root" or "require readOnlyRootFilesystem" or "require resource
# limits" policy in Enforce mode would, on the next reconciliation of ANY already-running
# Terraform-managed addon (Karpenter, the AWS Load Balancer Controller, NGINX, cert-manager,
# ExternalDNS, External Secrets Operator, kube-prometheus-stack, Loki, Tempo, the OTel Collector,
# ArgoCD itself), start rejecting updates to pods whose upstream Helm chart's default
# securityContext this phase did not audit line-by-line — and has no authority to change without
# redesigning those charts' values, explicitly out of scope ("Do NOT redesign anything"). Rather
# than guess which upstream defaults happen to already comply and which don't, every policy in
# this file matches ONLY `patheya-backend`/`patheya-frontend` — the two namespaces Phase 3 already
# put under Pod Security "restricted" specifically because they're the ones meant to hold
# reviewed, controlled application workloads. Every other namespace (kube-system, argocd,
# monitoring, logging, tracing, observability, external-secrets, cert-manager, ingress-nginx,
# data-platform, kyverno, trivy-system, falco) is untouched by this file — visibility into
# whether those charts' defaults happen to comply is a Trivy Operator ConfigAuditReport concern
# (trivy-operator.tf), not an admission-blocking one.

locals {
  app_namespaces = ["patheya-backend", "patheya-frontend"]
}

resource "kubernetes_manifest" "policy_disallow_latest_tag" {
  manifest = {
    apiVersion = "kyverno.io/v1"
    kind       = "ClusterPolicy"
    metadata = {
      name = "disallow-latest-tag"
      annotations = {
        "policies.kyverno.io/title"    = "Disallow Latest Tag"
        "policies.kyverno.io/severity" = "medium"
        "policies.kyverno.io/category" = "Best Practices"
      }
    }
    spec = {
      validationFailureAction = var.kyverno_policy_mode
      background              = true
      rules = [
        {
          name  = "require-image-tag"
          match = { any = [{ resources = { kinds = ["Pod"], namespaces = local.app_namespaces } }] }
          validate = {
            message = "Image tag ':latest' (or no tag at all) is not allowed — platform-standards.md Section 4 requires an immutable <semver>-<git-sha-short> tag."
            foreach = [
              {
                list = "request.object.spec.containers"
                deny = {
                  conditions = {
                    any = [
                      { key = "{{ contains(element.image, ':') }}", operator = "Equals", value = false },
                      { key = "{{ split(element.image, ':')[-1] }}", operator = "Equals", value = "latest" },
                    ]
                  }
                }
              }
            ]
          }
        }
      ]
    }
  }

  depends_on = [helm_release.kyverno]
}

resource "kubernetes_manifest" "policy_require_resource_requests_limits" {
  manifest = {
    apiVersion = "kyverno.io/v1"
    kind       = "ClusterPolicy"
    metadata = {
      name = "require-resource-requests-limits"
      annotations = {
        "policies.kyverno.io/title"    = "Require Resource Requests and Limits"
        "policies.kyverno.io/severity" = "medium"
        "policies.kyverno.io/category" = "Best Practices"
      }
    }
    spec = {
      validationFailureAction = var.kyverno_policy_mode
      background              = true
      rules = [
        {
          name  = "validate-resources"
          match = { any = [{ resources = { kinds = ["Pod"], namespaces = local.app_namespaces } }] }
          validate = {
            message = "Every container must set resources.requests and resources.limits for both cpu and memory — platform-standards.md Section 7."
            pattern = {
              spec = {
                containers = [
                  {
                    resources = {
                      requests = { cpu = "?*", memory = "?*" }
                      limits   = { cpu = "?*", memory = "?*" }
                    }
                  }
                ]
              }
            }
          }
        }
      ]
    }
  }

  depends_on = [helm_release.kyverno]
}

resource "kubernetes_manifest" "policy_require_probes" {
  manifest = {
    apiVersion = "kyverno.io/v1"
    kind       = "ClusterPolicy"
    metadata = {
      name = "require-probes"
      annotations = {
        "policies.kyverno.io/title"    = "Require Liveness and Readiness Probes"
        "policies.kyverno.io/severity" = "medium"
        "policies.kyverno.io/category" = "Best Practices"
      }
    }
    spec = {
      validationFailureAction = var.kyverno_policy_mode
      background              = true
      rules = [
        {
          name  = "validate-probes"
          match = { any = [{ resources = { kinds = ["Pod"], namespaces = local.app_namespaces } }] }
          validate = {
            message = "Every container must define livenessProbe and readinessProbe — docs/infrastructure/health-checks.md."
            pattern = {
              spec = {
                containers = [
                  { livenessProbe = "?*", readinessProbe = "?*" }
                ]
              }
            }
          }
        }
      ]
    }
  }

  depends_on = [helm_release.kyverno]
}

resource "kubernetes_manifest" "policy_require_non_root" {
  manifest = {
    apiVersion = "kyverno.io/v1"
    kind       = "ClusterPolicy"
    metadata = {
      name = "require-non-root"
      annotations = {
        "policies.kyverno.io/title"    = "Require Non-Root Containers"
        "policies.kyverno.io/severity" = "high"
        "policies.kyverno.io/category" = "Pod Security Standards (Restricted)"
      }
    }
    spec = {
      validationFailureAction = var.kyverno_policy_mode
      background              = true
      rules = [
        {
          name  = "run-as-non-root"
          match = { any = [{ resources = { kinds = ["Pod"], namespaces = local.app_namespaces } }] }
          validate = {
            message = "runAsNonRoot must be true, at the pod or every container's securityContext."
            anyPattern = [
              { spec = { securityContext = { runAsNonRoot = true } } },
              { spec = { containers = [{ securityContext = { runAsNonRoot = true } }] } },
            ]
          }
        }
      ]
    }
  }

  depends_on = [helm_release.kyverno]
}

resource "kubernetes_manifest" "policy_require_readonly_root_fs" {
  manifest = {
    apiVersion = "kyverno.io/v1"
    kind       = "ClusterPolicy"
    metadata = {
      name = "require-readonly-root-filesystem"
      annotations = {
        "policies.kyverno.io/title"    = "Require readOnlyRootFilesystem"
        "policies.kyverno.io/severity" = "high"
        "policies.kyverno.io/category" = "Best Practices"
      }
    }
    spec = {
      validationFailureAction = var.kyverno_policy_mode
      background              = true
      rules = [
        {
          name  = "readonly-root-fs"
          match = { any = [{ resources = { kinds = ["Pod"], namespaces = local.app_namespaces } }] }
          validate = {
            message = "Every container must set securityContext.readOnlyRootFilesystem: true — mount an emptyDir for any writable path a container genuinely needs (the backend repo's Dockerfile already documents exactly two: logs/ and uploads/)."
            pattern = {
              spec = {
                containers = [{ securityContext = { readOnlyRootFilesystem = true } }]
              }
            }
          }
        }
      ]
    }
  }

  depends_on = [helm_release.kyverno]
}

resource "kubernetes_manifest" "policy_require_pod_security_restricted" {
  manifest = {
    apiVersion = "kyverno.io/v1"
    kind       = "ClusterPolicy"
    metadata = {
      name = "require-pod-security-restricted"
      annotations = {
        "policies.kyverno.io/title"    = "Require Pod Security Standards (Restricted) Fields"
        "policies.kyverno.io/severity" = "high"
        "policies.kyverno.io/category" = "Pod Security Standards (Restricted)"
      }
    }
    spec = {
      # A second, independent layer on top of the API server's own PSA "restricted" enforcement
      # (the namespace labels Phase 3 already set) — zero trust (platform-standards.md Section 1,
      # principle 9) means not relying on exactly one control even when that control is already
      # believed sufficient. This rule checks the same fields PSA "restricted" checks
      # (allowPrivilegeEscalation, capabilities.drop, seccompProfile) explicitly, so a future PSA
      # label removed by mistake on these two namespaces isn't the only thing standing between a
      # pod and running privileged.
      validationFailureAction = var.kyverno_policy_mode
      background              = true
      rules = [
        {
          name  = "restricted-fields"
          match = { any = [{ resources = { kinds = ["Pod"], namespaces = local.app_namespaces } }] }
          validate = {
            message = "Pod Security Standards (Restricted): allowPrivilegeEscalation must be false, capabilities must drop ALL, seccompProfile must be RuntimeDefault or Localhost."
            pattern = {
              spec = {
                containers = [
                  {
                    securityContext = {
                      allowPrivilegeEscalation = false
                      capabilities             = { drop = ["ALL"] }
                    }
                  }
                ]
                "(securityContext.seccompProfile.type)" = "RuntimeDefault | Localhost"
              }
            }
          }
        }
      ]
    }
  }

  depends_on = [helm_release.kyverno]
}

resource "kubernetes_manifest" "policy_require_approved_registries" {
  manifest = {
    apiVersion = "kyverno.io/v1"
    kind       = "ClusterPolicy"
    metadata = {
      name = "require-approved-registries"
      annotations = {
        "policies.kyverno.io/title"    = "Require Approved Registries"
        "policies.kyverno.io/severity" = "high"
        "policies.kyverno.io/category" = "Supply Chain Security"
      }
    }
    spec = {
      validationFailureAction = var.kyverno_policy_mode
      background              = true
      rules = [
        {
          name  = "approved-registries-only"
          match = { any = [{ resources = { kinds = ["Pod"], namespaces = local.app_namespaces } }] }
          validate = {
            message = "Container images must come from this platform's own ECR registry (${var.ecr_registry_host}/patheya-express/*) — cloud-architecture-blueprint.md Section 9's build/scan/sign/push pipeline is the only trusted source for anything running in patheya-backend/patheya-frontend."
            foreach = [
              {
                list = "request.object.spec.containers"
                deny = {
                  conditions = {
                    any = [
                      { key = "{{ element.image }}", operator = "AnyNotIn", value = ["${var.ecr_registry_host}/patheya-express/*"] },
                    ]
                  }
                }
              }
            ]
          }
        }
      ]
    }
  }

  depends_on = [helm_release.kyverno]
}

resource "kubernetes_manifest" "policy_require_labels" {
  manifest = {
    apiVersion = "kyverno.io/v1"
    kind       = "ClusterPolicy"
    metadata = {
      name = "require-labels"
      annotations = {
        "policies.kyverno.io/title"    = "Require Standard Labels"
        "policies.kyverno.io/severity" = "low"
        "policies.kyverno.io/category" = "Best Practices"
      }
    }
    spec = {
      validationFailureAction = var.kyverno_policy_mode
      background              = true
      rules = [
        {
          name  = "require-app-kubernetes-io-labels"
          match = { any = [{ resources = { kinds = ["Pod"], namespaces = local.app_namespaces } }] }
          validate = {
            message = "Every pod must carry app.kubernetes.io/name, app.kubernetes.io/component, app.kubernetes.io/part-of, app.kubernetes.io/managed-by, app.kubernetes.io/version — platform-standards.md Section 7."
            pattern = {
              metadata = {
                labels = {
                  "app.kubernetes.io/name"       = "?*"
                  "app.kubernetes.io/component"  = "?*"
                  "app.kubernetes.io/part-of"    = "?*"
                  "app.kubernetes.io/managed-by" = "?*"
                  "app.kubernetes.io/version"    = "?*"
                }
              }
            }
          }
        }
      ]
    }
  }

  depends_on = [helm_release.kyverno]
}

resource "kubernetes_manifest" "policy_require_annotations" {
  manifest = {
    apiVersion = "kyverno.io/v1"
    kind       = "ClusterPolicy"
    metadata = {
      name = "require-annotations"
      annotations = {
        "policies.kyverno.io/title"    = "Require Traceability Annotations"
        "policies.kyverno.io/severity" = "low"
        "policies.kyverno.io/category" = "Best Practices"
      }
    }
    spec = {
      validationFailureAction = var.kyverno_policy_mode
      background              = true
      rules = [
        {
          name  = "require-source-annotations"
          match = { any = [{ resources = { kinds = ["Pod"], namespaces = local.app_namespaces } }] }
          validate = {
            message = "Every pod must carry patheya-express.io/git-commit and patheya-express.io/build-id — traces a running pod back to the exact CI run that produced it (matching platform-standards.md Section 10's artifact-naming/traceability requirement), once CI exists to set them."
            pattern = {
              metadata = {
                annotations = {
                  "patheya-express.io/git-commit" = "?*"
                  "patheya-express.io/build-id"   = "?*"
                }
              }
            }
          }
        }
      ]
    }
  }

  depends_on = [helm_release.kyverno]
}

resource "kubernetes_manifest" "policy_block_privileged" {
  manifest = {
    apiVersion = "kyverno.io/v1"
    kind       = "ClusterPolicy"
    metadata = {
      name = "block-privileged-containers"
      annotations = {
        "policies.kyverno.io/title"    = "Block Privileged Containers"
        "policies.kyverno.io/severity" = "critical"
        "policies.kyverno.io/category" = "Pod Security Standards (Baseline)"
      }
    }
    spec = {
      validationFailureAction = var.kyverno_policy_mode
      background              = true
      rules = [
        {
          name  = "no-privileged"
          match = { any = [{ resources = { kinds = ["Pod"], namespaces = local.app_namespaces } }] }
          validate = {
            message = "Privileged containers are never allowed in patheya-backend/patheya-frontend."
            pattern = {
              spec = {
                containers = [{ "=(securityContext.privileged)" = "false" }]
              }
            }
          }
        }
      ]
    }
  }

  depends_on = [helm_release.kyverno]
}

resource "kubernetes_manifest" "policy_block_host_namespaces" {
  manifest = {
    apiVersion = "kyverno.io/v1"
    kind       = "ClusterPolicy"
    metadata = {
      name = "block-host-namespaces"
      annotations = {
        "policies.kyverno.io/title"    = "Block hostNetwork, hostPID, hostIPC"
        "policies.kyverno.io/severity" = "critical"
        "policies.kyverno.io/category" = "Pod Security Standards (Baseline)"
      }
    }
    spec = {
      validationFailureAction = var.kyverno_policy_mode
      background              = true
      rules = [
        {
          name  = "no-host-namespaces"
          match = { any = [{ resources = { kinds = ["Pod"], namespaces = local.app_namespaces } }] }
          validate = {
            message = "hostNetwork, hostPID, and hostIPC are never allowed in patheya-backend/patheya-frontend — none of these workloads need host namespace access."
            pattern = {
              spec = {
                "=(hostNetwork)" = "false"
                "=(hostPID)"     = "false"
                "=(hostIPC)"     = "false"
              }
            }
          }
        }
      ]
    }
  }

  depends_on = [helm_release.kyverno]
}

resource "kubernetes_manifest" "policy_block_unsafe_capabilities" {
  manifest = {
    apiVersion = "kyverno.io/v1"
    kind       = "ClusterPolicy"
    metadata = {
      name = "block-unsafe-capabilities"
      annotations = {
        "policies.kyverno.io/title"    = "Block Unsafe Capabilities"
        "policies.kyverno.io/severity" = "high"
        "policies.kyverno.io/category" = "Pod Security Standards (Restricted)"
      }
    }
    spec = {
      validationFailureAction = var.kyverno_policy_mode
      background              = true
      rules = [
        {
          name  = "no-added-capabilities"
          match = { any = [{ resources = { kinds = ["Pod"], namespaces = local.app_namespaces } }] }
          validate = {
            message = "No container may add any Linux capability — combined with block-privileged-containers, this is the enforcement half of require-pod-security-restricted's capabilities.drop check."
            foreach = [
              {
                list = "request.object.spec.containers"
                deny = {
                  conditions = {
                    any = [
                      { key = "{{ length(element.securityContext.capabilities.add || `[]`) }}", operator = "GreaterThan", value = 0 },
                    ]
                  }
                }
              }
            ]
          }
        }
      ]
    }
  }

  depends_on = [helm_release.kyverno]
}

resource "kubernetes_manifest" "policy_block_hostpath_volumes" {
  manifest = {
    apiVersion = "kyverno.io/v1"
    kind       = "ClusterPolicy"
    metadata = {
      name = "block-hostpath-volumes"
      annotations = {
        "policies.kyverno.io/title"    = "Block hostPath Volumes"
        "policies.kyverno.io/severity" = "critical"
        "policies.kyverno.io/category" = "Pod Security Standards (Baseline)"
      }
    }
    spec = {
      validationFailureAction = var.kyverno_policy_mode
      background              = true
      rules = [
        {
          name  = "no-hostpath"
          match = { any = [{ resources = { kinds = ["Pod"], namespaces = local.app_namespaces } }] }
          validate = {
            message = "hostPath volumes are never allowed — every writable path this platform's workloads need (logs/, uploads/) is an emptyDir, per the backend repo's own Dockerfile/k8s manifests."
            deny = {
              conditions = {
                any = [
                  { key = "{{ request.object.spec.volumes[?hostPath][] || `[]` | length(@) }}", operator = "GreaterThan", value = 0 },
                ]
              }
            }
          }
        }
      ]
    }
  }

  depends_on = [helm_release.kyverno]
}
