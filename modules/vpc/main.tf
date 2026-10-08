resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-vpc"
    Application = "vpc"
    Purpose     = "primary-vpc"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-igw"
    Application = "vpc"
    Purpose     = "internet-gateway"
  })
}

# --- Subnets ------------------------------------------------------------------------------------

resource "aws_subnet" "public" {
  count = 3

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false # NLB/NAT get Elastic IPs explicitly — no instance in this subnet auto-assigns a public IP

  tags = merge(var.tags, {
    Name                     = "${var.name_prefix}-public-${var.availability_zones[count.index]}"
    Application              = "vpc"
    Purpose                  = "public-subnet"
    "kubernetes.io/role/elb" = "1" # AWS Load Balancer Controller subnet auto-discovery, Phase 3
  })
}

resource "aws_subnet" "private_app" {
  count = 3

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_app_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name                              = "${var.name_prefix}-private-app-${var.availability_zones[count.index]}"
    Application                       = "vpc"
    Purpose                           = "private-application-subnet"
    "kubernetes.io/role/internal-elb" = "1" # internal NLB/ALB auto-discovery, Phase 3
  })
}

resource "aws_subnet" "private_data" {
  count = 3

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_data_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-private-data-${var.availability_zones[count.index]}"
    Application = "vpc"
    Purpose     = "private-data-subnet"
  })
}

# --- NAT ----------------------------------------------------------------------------------------

# enable_nat_gateway = false removes every NAT Gateway, its EIP, and every private-app default
# route together - the topology (single vs per-AZ) is still decided solely by single_nat_gateway,
# so re-enabling always restores exactly the same shape.
locals {
  nat_gateway_count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : 3) : 0
}

# Safe ordering for NAT topology changes (single_nat_gateway / enable_nat_gateway flips). On
# 2026-10-08 a 3 -> 1 change destroyed NAT Gateways before the private-app routes that used them
# were re-pointed: Terraform only guarantees "update dependents before destroying a dependency"
# for create_before_destroy resources, so the route updates and NAT destroys ran in parallel and
# two AZs lost egress. The chain below makes the order explicit:
#
#   create:  EIP -> time_sleep -> NAT Gateway -> private-app routes
#   destroy: private-app routes re-pointed/removed -> NAT Gateway -> wait -> EIP released
#
# create_before_destroy on EIP, time_sleep and NAT Gateway defers every NAT/EIP destroy until all
# dependent routes have been updated to their new target. The time_sleep's destroy_duration holds
# the EIP release until the deleted NAT Gateway's network interface is gone (ReleaseAddress
# otherwise fails with InvalidNetworkInterfaceID.NotFound, as it did on 2026-10-08).
#
# Limitation: a NAT Gateway cannot be replaced in place (e.g. a subnet_id change) while keeping its
# EIP, since create_before_destroy needs the EIP free for the new gateway. Change topology through
# single_nat_gateway / enable_nat_gateway, which add/remove EIP+NAT pairs together.
resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  tags = merge(var.tags, {
    Name        = var.single_nat_gateway ? "${var.name_prefix}-eip-nat" : "${var.name_prefix}-eip-nat-${var.availability_zones[count.index]}"
    Application = "vpc"
    Purpose     = "nat-gateway-eip"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "time_sleep" "nat_eip_release" {
  count = local.nat_gateway_count

  triggers = {
    allocation_id = aws_eip.nat[count.index].id
  }

  destroy_duration = "120s"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  # Through time_sleep (same value as aws_eip.nat[count.index].id) so the NAT Gateway is destroyed
  # before the wait, and the EIP is released only after it.
  allocation_id = time_sleep.nat_eip_release[count.index].triggers["allocation_id"]
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, {
    Name        = var.single_nat_gateway ? "${var.name_prefix}-nat" : "${var.name_prefix}-nat-${var.availability_zones[count.index]}"
    Application = "vpc"
    Purpose     = "nat-gateway"
  })

  depends_on = [aws_internet_gateway.this]

  lifecycle {
    create_before_destroy = true
  }
}

# --- Route tables ---------------------------------------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-public-rt"
    Application = "vpc"
    Purpose     = "public-route-table"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = 3

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# One route table per AZ for private-app subnets — each routes 0.0.0.0/0 to its OWN AZ's NAT
# Gateway (or the single shared one), never a cross-AZ NAT hop, per cloud-architecture-blueprint.md
# Section 2's explicit reasoning (keeps a single-AZ NAT failure's blast radius to that AZ only).
resource "aws_route_table" "private_app" {
  count = 3

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-private-app-rt-${var.availability_zones[count.index]}"
    Application = "vpc"
    Purpose     = "private-application-route-table"
  })
}

resource "aws_route" "private_app_nat" {
  count = var.enable_nat_gateway ? 3 : 0 # no default route at all rather than one pointing at a NAT Gateway that doesn't exist

  route_table_id         = aws_route_table.private_app[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.single_nat_gateway ? aws_nat_gateway.this[0].id : aws_nat_gateway.this[count.index].id

  # Explicit (not only via the reference above, which names a single instance): every NAT Gateway
  # instance's destroy waits on these route updates — see the NAT section's ordering comment.
  depends_on = [aws_nat_gateway.this]
}

resource "aws_route_table_association" "private_app" {
  count = 3

  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app[count.index].id
}

# Private data subnets get a route table with NO default route at all — Aurora/ElastiCache are
# reachable only from inside the VPC, full stop (cloud-architecture-blueprint.md Section 2).
resource "aws_route_table" "private_data" {
  count = 3

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name        = "${var.name_prefix}-private-data-rt-${var.availability_zones[count.index]}"
    Application = "vpc"
    Purpose     = "private-data-route-table"
  })
}

resource "aws_route_table_association" "private_data" {
  count = 3

  subnet_id      = aws_subnet.private_data[count.index].id
  route_table_id = aws_route_table.private_data[count.index].id
}
