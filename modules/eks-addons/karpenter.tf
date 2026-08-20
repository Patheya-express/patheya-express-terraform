# --- Interruption handling: SQS queue + EventBridge rules (this task's Section 10) -------------
resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = "${var.name_prefix}-karpenter-interruption"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true

  tags = merge(var.tags, { Application = "eks-addons", Purpose = "karpenter-interruption-queue" })
}

data "aws_iam_policy_document" "karpenter_interruption_queue" {
  statement {
    sid       = "AllowEventBridgeAndASGToSendMessages"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.karpenter_interruption.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }
  }
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.id
  policy    = data.aws_iam_policy_document.karpenter_interruption_queue.json
}

resource "aws_cloudwatch_event_rule" "spot_interruption" {
  name          = "${var.name_prefix}-karpenter-spot-interruption"
  event_pattern = jsonencode({ source = ["aws.ec2"], "detail-type" = ["EC2 Spot Instance Interruption Warning"] })
  tags          = merge(var.tags, { Application = "eks-addons", Purpose = "karpenter-spot-interruption-rule" })
}

resource "aws_cloudwatch_event_rule" "rebalance_recommendation" {
  name          = "${var.name_prefix}-karpenter-rebalance"
  event_pattern = jsonencode({ source = ["aws.ec2"], "detail-type" = ["EC2 Instance Rebalance Recommendation"] })
  tags          = merge(var.tags, { Application = "eks-addons", Purpose = "karpenter-rebalance-rule" })
}

resource "aws_cloudwatch_event_rule" "instance_state_change" {
  name          = "${var.name_prefix}-karpenter-state-change"
  event_pattern = jsonencode({ source = ["aws.ec2"], "detail-type" = ["EC2 Instance State-change Notification"] })
  tags          = merge(var.tags, { Application = "eks-addons", Purpose = "karpenter-state-change-rule" })
}

resource "aws_cloudwatch_event_target" "spot_interruption" {
  rule = aws_cloudwatch_event_rule.spot_interruption.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_target" "rebalance_recommendation" {
  rule = aws_cloudwatch_event_rule.rebalance_recommendation.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_target" "instance_state_change" {
  rule = aws_cloudwatch_event_rule.instance_state_change.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

# --- Karpenter controller IRSA -------------------------------------------------------------------
data "aws_iam_policy_document" "karpenter_controller_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:kube-system:karpenter"]
    }
    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter_controller" {
  name               = "${var.name_prefix}-karpenter-controller-role"
  assume_role_policy = data.aws_iam_policy_document.karpenter_controller_assume.json

  tags = merge(var.tags, { Application = "eks-addons", Purpose = "karpenter-controller-irsa-role" })
}

data "aws_iam_policy_document" "karpenter_controller" {
  statement {
    sid    = "AllowScopedEC2InstanceActions"
    effect = "Allow"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate",
      "ec2:CreateTags",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}::image/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}::snapshot/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:spot-instances-request/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:security-group/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:subnet/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:launch-template/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:fleet/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:volume/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:network-interface/*",
    ]
  }

  statement {
    sid    = "AllowUnscopedReadActions"
    effect = "Allow"
    actions = [
      "ec2:DescribeImages", "ec2:DescribeInstances", "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstanceTypeOfferings", "ec2:DescribeAvailabilityZones", "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSpotPriceHistory", "ec2:DescribeSubnets", "ec2:DescribeSecurityGroups",
      "pricing:GetProducts",
      "ssm:GetParameter",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "AllowInstanceProfileManagement"
    effect    = "Allow"
    actions   = ["iam:CreateInstanceProfile", "iam:TagInstanceProfile", "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile"]
    resources = ["*"]
  }

  statement {
    sid       = "AllowPassingNodeRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${var.node_role_name}"]
  }

  statement {
    sid       = "AllowTerminatingInterruptedNodes"
    effect    = "Allow"
    actions   = ["ec2:TerminateInstances"]
    resources = ["*"]
    condition {
      test     = "StringLike"
      variable = "ec2:ResourceTag/karpenter.sh/nodepool"
      values   = ["*"]
    }
  }

  statement {
    sid       = "AllowInterruptionQueueConsumption"
    effect    = "Allow"
    actions   = ["sqs:DeleteMessage", "sqs:GetQueueUrl", "sqs:ReceiveMessage"]
    resources = [aws_sqs_queue.karpenter_interruption.arn]
  }

  statement {
    sid       = "AllowEKSDescribe"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:${data.aws_partition.current.partition}:eks:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"]
  }
}

resource "aws_iam_role_policy" "karpenter_controller" {
  name   = "${var.name_prefix}-karpenter-controller-policy"
  role   = aws_iam_role.karpenter_controller.id
  policy = data.aws_iam_policy_document.karpenter_controller.json
}

resource "aws_iam_instance_profile" "karpenter_node" {
  name = "${var.name_prefix}-karpenter-node-profile"
  role = var.node_role_name

  tags = merge(var.tags, { Application = "eks-addons", Purpose = "karpenter-node-instance-profile" })
}

resource "helm_release" "karpenter" {
  name       = "karpenter"
  namespace  = "kube-system"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "1.0.6"
  wait       = true
  atomic     = true

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.karpenter_controller.arn
  }
  set {
    name  = "settings.clusterName"
    value = var.cluster_name
  }
  set {
    name  = "settings.interruptionQueue"
    value = aws_sqs_queue.karpenter_interruption.name
  }
  set {
    name  = "replicas"
    value = var.environment_tier == "production" ? 2 : 1
  }
  # Runs on the system node group, never on a Karpenter-provisioned (and thus potentially
  # spot-interruptible) node — Karpenter managing its own scale-down risk is a real failure mode.
  set {
    name  = "nodeSelector.patheya-express\\.io/node-role"
    value = "system"
  }
  set {
    name  = "tolerations[0].key"
    value = "CriticalAddonsOnly"
  }
  set {
    name  = "tolerations[0].operator"
    value = "Exists"
  }
}

# --- NodePools / EC2NodeClasses -------------------------------------------------------------------
resource "kubernetes_manifest" "karpenter_ec2_node_class" {
  manifest = {
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "default"
    }
    spec = {
      amiFamily = "AL2023"
      role      = var.node_role_name
      subnetSelectorTerms = [
        { tags = { "kubernetes.io/role/internal-elb" = "1" } }
      ]
      securityGroupSelectorTerms = [
        { id = var.eks_node_security_group_id }
      ]
      tags = merge(var.tags, { Application = "eks-addons", Purpose = "karpenter-node" })
    }
  }

  depends_on = [helm_release.karpenter]
}

resource "kubernetes_manifest" "karpenter_nodepool_general_purpose" {
  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "general-purpose"
    }
    spec = {
      template = {
        spec = {
          nodeClassRef = { group = "karpenter.k8s.aws", kind = "EC2NodeClass", name = "default" }
          requirements = [
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["on-demand"] },
            { key = "node.kubernetes.io/instance-family", operator = "In", values = var.karpenter_instance_families },
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
          ]
        }
      }
      # Empty limits = no explicit ceiling here; the real ceiling is the on-demand baseline the
      # managed "application" node group already provides (modules/eks) plus whatever this
      # NodePool and the spot pool below add — cost control happens via Karpenter's own
      # consolidation, not an artificial resource cap that would just cause pending pods.
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "1m"
      }
    }
  }

  depends_on = [kubernetes_manifest.karpenter_ec2_node_class]
}

resource "kubernetes_manifest" "karpenter_nodepool_spot" {
  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "general-purpose-spot"
    }
    spec = {
      template = {
        spec = {
          nodeClassRef = { group = "karpenter.k8s.aws", kind = "EC2NodeClass", name = "default" }
          requirements = [
            { key = "karpenter.sh/capacity-type", operator = "In", values = ["spot"] },
            { key = "node.kubernetes.io/instance-family", operator = "In", values = var.karpenter_instance_families },
            { key = "kubernetes.io/arch", operator = "In", values = ["amd64"] },
          ]
        }
      }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "30s" # more aggressive than the on-demand pool — spot capacity is meant to be reclaimed quickly once idle, that's the cost model
        budgets = [
          { nodes = "50%" } # never disrupt more than half of spot nodes at once — cloud-architecture-blueprint.md Section 14's PDB-protected spot strategy extends to Karpenter's own voluntary disruption, not just node-level interruption
        ]
      }
    }
  }

  depends_on = [kubernetes_manifest.karpenter_ec2_node_class]
}
