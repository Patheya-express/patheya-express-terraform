# Alert naming follows platform-standards.md Section 12's <Severity>-<Service>-<Condition>
# convention, same as every PrometheusRule modules/observability already created.

resource "kubernetes_manifest" "supply_chain_alerts" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "patheya-supply-chain-alerts"
      namespace = "monitoring"
      labels    = { release = "kube-prometheus-stack" }
    }
    spec = {
      groups = [
        {
          name = "patheya.supply-chain"
          rules = [
            {
              alert       = "Critical-Kyverno-AdmissionControllerDown"
              expr        = "absent(up{namespace=\"kyverno\", pod=~\"kyverno-admission-controller.*\"} == 1)"
              for         = "5m"
              labels      = { severity = "critical" }
              annotations = { summary = "No Kyverno admission-controller pod is up — depending on failurePolicy, either every pod create in the cluster is now blocked, or admission policy enforcement has silently stopped." }
            },
            {
              alert       = "Warning-Kyverno-PolicyViolationsHigh"
              expr        = "sum(increase(kyverno_policy_results_total{rule_result=\"fail\"}[15m])) by (policy_name) > 10"
              for         = "0m"
              labels      = { severity = "warning" }
              annotations = { summary = "Kyverno policy {{ $labels.policy_name }} has failed more than 10 times in 15 minutes — check whether this is a misconfigured deploy or a policy that needs an exception (docs/exception-process.md)." }
            },
            {
              alert       = "Critical-Trivy-CriticalVulnerabilityFound"
              expr        = "sum(trivy_image_vulnerabilities{severity=\"Critical\"}) by (namespace, image_repository) > 0"
              for         = "0m"
              labels      = { severity = "critical" }
              annotations = { summary = "A CRITICAL-severity CVE was found in {{ $labels.namespace }}/{{ $labels.image_repository }} by Trivy Operator's in-cluster rescan." }
            },
            {
              alert       = "Warning-Trivy-HighVulnerabilityFound"
              expr        = "sum(trivy_image_vulnerabilities{severity=\"High\"}) by (namespace, image_repository) > 5"
              for         = "0m"
              labels      = { severity = "warning" }
              annotations = { summary = "More than 5 HIGH-severity CVEs found in {{ $labels.namespace }}/{{ $labels.image_repository }}." }
            },
            {
              alert       = "Critical-Falco-RuntimeAlertTriggered"
              expr        = "sum(increase(falco_events{priority=~\"Critical|Emergency|Alert\"}[5m])) by (rule) > 0"
              for         = "0m"
              labels      = { severity = "critical" }
              annotations = { summary = "Falco rule \"{{ $labels.rule }}\" fired at Critical/Emergency/Alert priority — a running container did something its image/signature/admission checks were never positioned to catch. See docs/incident-response.md." }
            },
            {
              alert       = "Warning-Falco-DaemonSetNotFullyScheduled"
              expr        = "kube_daemonset_status_number_ready{namespace=\"falco\", daemonset=\"falco\"} < kube_daemonset_status_desired_number_scheduled{namespace=\"falco\", daemonset=\"falco\"}"
              for         = "10m"
              labels      = { severity = "warning" }
              annotations = { summary = "Falco is not running on every node — the nodes it's missing from have zero runtime detection coverage." }
            },
          ]
        }
      ]
    }
  }

  depends_on = [helm_release.kyverno, helm_release.trivy_operator, helm_release.falco]
}
