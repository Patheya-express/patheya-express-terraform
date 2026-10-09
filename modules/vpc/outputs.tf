output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  value = aws_subnet.private_app[*].id
}

output "private_data_subnet_ids" {
  value = aws_subnet.private_data[*].id
}

output "private_app_route_table_ids" {
  description = "For gateway VPC endpoints (e.g. S3) serving the private-app tier."
  value       = aws_route_table.private_app[*].id
}

output "nat_gateway_ids" {
  value = aws_nat_gateway.this[*].id
}

output "internet_gateway_id" {
  value = aws_internet_gateway.this.id
}

output "availability_zones" {
  value = var.availability_zones
}
