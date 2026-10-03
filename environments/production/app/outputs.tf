output "api_url" {
  value = "https://${local.api_domain}"
}

output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "web_acl_arn" {
  value = module.waf.web_acl_arn
}

output "operating_mode" {
  value = var.operating_mode
}

# Everything backend-deploy-ecs.yml needs, as the `production` GitHub Environment variables it
# reads (docs/production-lifecycle.md lists the mapping). No secrets.
output "ecs_deploy_settings" {
  value = {
    cluster_name                = module.ecs.cluster_name
    api_service_name            = module.ecs.api_service_name
    worker_service_name         = module.ecs.worker_service_name
    api_task_family             = module.ecs.api_task_definition_family
    worker_task_family          = module.ecs.worker_task_definition_family
    migration_task_family       = module.ecs.migration_task_definition_family
    migration_container_name    = "migrate"
    migration_log_group_name    = module.ecs.migration_log_group_name
    migration_subnet_ids        = local.network.private_app_subnet_ids
    migration_security_group_id = local.network.ecs_migration_security_group_id
    image_repository_url        = local.image_repository_url
  }
}

output "static_site_deploy_settings" {
  description = "Per site: the bucket the frontend deploy workflow syncs and the distribution it invalidates."
  value = {
    for site in keys(local.site_domains) : site => {
      domain          = local.site_domains[site]
      bucket_name     = module.static_site.bucket_names[site]
      distribution_id = module.static_site.distribution_ids[site]
    }
  }
}

# Live-mode worst case: both services at max capacity mid-rollout (deployment_maximum_percent) plus
# one migration task. Fails the plan rather than letting a deploy stall on Fargate quota.
output "fargate_peak_vcpu" {
  value = local.live_peak_vcpu

  precondition {
    condition     = local.live_peak_vcpu <= var.fargate_on_demand_vcpu_quota
    error_message = "Live-mode peak Fargate demand (${local.live_peak_vcpu} vCPU incl. deployment surge) exceeds the ${var.fargate_on_demand_vcpu_quota} vCPU quota — lower max capacities / deployment_maximum_percent or raise the quota first."
  }
}
