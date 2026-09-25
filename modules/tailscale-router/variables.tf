variable "tags" {
  type = map(string)
}

variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "private_app_subnet_ids" {
  description = "All three, passed to the ASG so AWS can place the single instance in whichever AZ has capacity for var.instance_type - a fixed single subnet risks an AZ-specific capacity shortfall (observed with t4g.nano in ap-south-1a) blocking the only instance this ASG ever runs."
  type        = list(string)
}

variable "advertised_route_cidrs" {
  description = "CIDR(s) advertised into the tailnet via `tailscale up --advertise-routes`. Must be scoped to exactly what needs reaching (the private-app subnets where the EKS control-plane ENIs live) — never the whole VPC CIDR, which would also expose the private-data tier (Aurora/Redis) to anyone on the tailnet."
  type        = list(string)
}

variable "kms_key_arn" {
  description = "Encrypts the Tailscale auth-key secret."
  type        = string
}

variable "permission_boundary_arn" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t4g.micro" # 1 GiB RAM - t4g.nano's 0.5 GiB was insufficient for `dnf install` at boot (confirmed via an OOM kill in production); runtime packet-forwarding load itself is still trivial, this is purely an install-time headroom requirement
}
