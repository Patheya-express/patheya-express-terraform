data "aws_iam_policy_document" "node_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Shared by both managed node groups AND Karpenter-provisioned nodes (modules/eks-addons'
# EC2NodeClass references this same role by name) — one node identity for the whole cluster,
# not a separate role per node group with no meaningful permission difference between them.
resource "aws_iam_role" "node" {
  name               = "${var.name_prefix}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json

  tags = merge(var.tags, { Application = "eks", Purpose = "eks-node-role" })
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Session Manager, not SSH — no bastion host, no SSH key pair anywhere in this platform
# (platform-standards.md Section 1 principle 9, zero trust: SSH access is a standing network
# path into every node; Session Manager is IAM-authorized, audited via CloudTrail, and requires
# no open port at all).
resource "aws_iam_role_policy_attachment" "node_ssm_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "node_ebs_csi_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_node_group" "system" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "system"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_app_subnet_ids

  instance_types = var.system_node_instance_types
  capacity_type  = "ON_DEMAND"

  scaling_config {
    desired_size = var.system_node_desired_size
    min_size     = var.system_node_min_size
    max_size     = var.system_node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    "patheya-express.io/node-role" = "system"
  }

  taint {
    key    = "CriticalAddonsOnly"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  tags = merge(var.tags, { Application = "eks", Purpose = "system-node-group" })

  # desired_size is deliberately Terraform-owned (no ignore_changes): nothing in this platform
  # resizes managed node groups at runtime — Karpenter provisions its own nodes above this floor
  # and there is no cluster-autoscaler — and ignoring it made min_size increases (e.g. an
  # environment moving to a larger operating mode) fail against a smaller live desired_size.
  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_policy,
    aws_eks_addon.before_compute,
  ]
}

resource "aws_eks_node_group" "application" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "application"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_app_subnet_ids

  instance_types = var.application_node_instance_types
  capacity_type  = "ON_DEMAND"

  scaling_config {
    desired_size = var.application_node_desired_size
    min_size     = var.application_node_min_size
    max_size     = var.application_node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    "patheya-express.io/node-role" = "application"
  }

  tags = merge(var.tags, { Application = "eks", Purpose = "application-node-group" })

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_policy,
    aws_eks_addon.before_compute,
  ]
}
