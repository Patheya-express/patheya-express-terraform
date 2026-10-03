# VPC endpoints for the private-app tier (ECS Fargate tasks).
#
# S3 gateway endpoint — free, and on the hot path: ECR serves image layers from S3, so every task
# launch pulls through it instead of through a NAT Gateway (no per-GB NAT processing charge). The
# default policy (full access) is kept deliberately: a gateway endpoint policy that is too narrow
# would silently break ECR layer downloads, which are fetched from AWS-owned buckets.
#
# No interface endpoints (ECR API, Secrets Manager, CloudWatch Logs, SSM): at ~USD 24/month each
# across three AZs they only pay for themselves at traffic levels Production has not reached, and
# the NAT Gateways they would replace stay mandatory anyway for Cloudinary/Razorpay/SMTP egress.
# Revisit with real NAT data-processing figures after launch.

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_app_route_table_ids

  tags = merge(module.shared.tags, {
    Name        = "${module.shared.name_prefix}-s3-gateway-endpoint"
    Application = "vpc"
    Purpose     = "s3-gateway-endpoint"
  })
}
