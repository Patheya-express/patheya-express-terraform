# Tailscale subnet router — the human-administrator path into the Production EKS private API
# endpoint. Requires CAP_NET_ADMIN + /dev/net/tun for IP forwarding, which AWS Fargate does not
# expose to containers — this is why it's EC2, not ECS, unlike every other lightweight service in
# this repository. No SSH, no key pair, no bastion: SSM Session Manager only, matching
# modules/eks/README.md's "Session Manager, not SSH" principle.

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

# The SSM public parameter for "latest plain Amazon Linux 2023" - not an `aws_ami` name-glob
# lookup. A glob like "al2023-ami-*-arm64" also matches the ECS-optimized variant
# ("al2023-ami-ecs-hvm-*-arm64", which ships Docker/containerd/the ECS agent pre-installed and
# running) - confirmed the hard way: that variant's baseline memory footprint, combined with
# t4g.nano's 0.5 GiB RAM, OOM-killed the `dnf install -y tailscale` step during boot before
# Tailscale was ever installed. This SSM parameter path is AWS's own documented, unambiguous way
# to reference the plain AMI with no risk of matching a specialized variant.
data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

# --- Secret (empty container; a human populates the value out-of-band, same pattern as
# modules/secrets-manager's external_credentials — see this module's README) -----------------------

resource "aws_secretsmanager_secret" "tailscale_authkey" {
  name        = "patheya-express/production/tailscale-router-authkey"
  description = "Tailscale auth key for the Production subnet router - value populated out-of-band by a human via `aws secretsmanager put-secret-value`, never by Terraform. Reusable, pre-approved keys are strongly discouraged - prefer a key with a short expiry, rotated whenever the instance is replaced."
  kms_key_id  = var.kms_key_arn

  tags = merge(var.tags, { Application = "tailscale-router", Purpose = "tailscale-authkey" })
}

# --- IAM ---------------------------------------------------------------------------------------

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = "${var.name_prefix}-tailscale-router-role"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  permissions_boundary = var.permission_boundary_arn

  tags = merge(var.tags, { Application = "tailscale-router", Purpose = "instance-role" })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "authkey_read" {
  statement {
    sid       = "ReadOwnAuthKeyOnly"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.tailscale_authkey.arn]
  }

  statement {
    sid       = "DecryptOwnAuthKeyOnly"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "authkey_read" {
  name   = "${var.name_prefix}-tailscale-router-authkey-read"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.authkey_read.json
}

resource "aws_iam_instance_profile" "this" {
  name = "${var.name_prefix}-tailscale-router-profile"
  role = aws_iam_role.this.name

  tags = merge(var.tags, { Application = "tailscale-router", Purpose = "instance-profile" })
}

# --- Security group — egress-only. Tailscale needs no inbound port opened anywhere; it connects
# outbound to Tailscale's coordination/DERP infrastructure and establishes direct (or
# relayed-but-still-outbound-initiated) WireGuard sessions. Nothing in this repository's existing
# security groups references this one as an ingress source except modules/networking's eks_nodes
# rule, added separately (that ingress lives on eks_nodes, not here, since it's the target that
# defines who may reach it) --------------------------------------------------------------------

resource "aws_security_group" "this" {
  name_prefix = "${var.name_prefix}-tailscale-router-"
  description = "Tailscale subnet router - outbound only, no inbound from the internet."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-tailscale-router-sg"
    Application = "tailscale-router"
    Purpose     = "tailscale-router-security-group"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "https_internet" {
  security_group_id = aws_security_group.this.id
  description       = "HTTPS to Tailscale coordination server and DERP relays - no fixed IP range, Tailscale own infrastructure."
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "wireguard" {
  security_group_id = aws_security_group.this.id
  description       = "Tailscale WireGuard-based direct-connection port - NAT traversal / DERP fallback."
  ip_protocol       = "udp"
  from_port         = 41641
  to_port           = 41641
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "vpc_forwarding" {
  security_group_id = aws_security_group.this.id
  description       = "Forwarded traffic into this VPC toward the EKS control-plane ENIs, this SG is the source referenced by eks_nodes ingress rule - scoped to this VPC own CIDR only, not a broader RFC1918 range."
  ip_protocol       = "-1"
  cidr_ipv4         = var.vpc_cidr
}

# --- Launch template + Auto Scaling Group (size 1 - self-healing, not highly-available; a
# management-plane path tolerates a brief restart on instance replacement, unlike a data path) -----

resource "aws_launch_template" "this" {
  name_prefix   = "${var.name_prefix}-tailscale-router-"
  image_id      = data.aws_ssm_parameter.al2023_arm64.value
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.this.arn
  }

  vpc_security_group_ids = [aws_security_group.this.id]

  metadata_options {
    http_tokens   = "required" # IMDSv2 only - matches the org-wide require-imds-v2 SCP
    http_endpoint = "enabled"
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -euo pipefail
    exec > >(tee /var/log/tailscale-setup.log | logger -t tailscale-setup -s) 2>&1

    # Tailscale's own official installer - not a raw `dnf install`, which fails on AL2023's default
    # repos (they do not carry the tailscale package; this script adds Tailscale's own repo first,
    # correctly, for whatever distro it detects).
    curl -fsSL https://tailscale.com/install.sh | sh
    systemctl enable --now tailscaled

    # sysctl IP forwarding - required for subnet-router mode
    echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.d/99-tailscale.conf
    echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.d/99-tailscale.conf
    sysctl -p /etc/sysctl.d/99-tailscale.conf

    AUTHKEY=$(aws secretsmanager get-secret-value \
      --secret-id "${aws_secretsmanager_secret.tailscale_authkey.arn}" \
      --region "${data.aws_region.current.name}" \
      --query SecretString --output text)

    tailscale up \
      --authkey="$AUTHKEY" \
      --advertise-routes="${join(",", var.advertised_route_cidrs)}" \
      --accept-dns=false \
      --ssh=false \
      --hostname="${var.name_prefix}-tailscale-router"

    echo "tailscale-router-setup-complete: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.tags, {
      Name        = "${var.name_prefix}-tailscale-router"
      Application = "tailscale-router"
      Purpose     = "subnet-router-instance"
    })
  }

  tags = merge(var.tags, { Application = "tailscale-router", Purpose = "launch-template" })
}

data "aws_region" "current" {}

resource "aws_autoscaling_group" "this" {
  name_prefix = "${var.name_prefix}-tailscale-router-"
  # Excludes index 0 (ap-south-1a, private_app_subnet_ids[0] - modules/vpc/main.tf's
  # aws_subnet.private_app is count-indexed against var.availability_zones in the same order the
  # calling environment passes it, so this ordering is deterministic, not assumed). Two consecutive
  # launch failures reported "insufficient t4g.nano capacity in ap-south-1a" and explicitly named
  # ap-south-1b/ap-south-1c as currently available - excluding the known-bad AZ outright rather
  # than relying on the ASG's own placement algorithm to route around it, which it wasn't doing.
  vpc_zone_identifier = slice(var.private_app_subnet_ids, 1, length(var.private_app_subnet_ids))
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}-tailscale-router"
    propagate_at_launch = true
  }
}
