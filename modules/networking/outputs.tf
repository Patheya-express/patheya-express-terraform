output "nlb_security_group_id" {
  value = aws_security_group.nlb.id
}

output "eks_node_security_group_id" {
  value = aws_security_group.eks_nodes.id
}

output "aurora_security_group_id" {
  value = aws_security_group.aurora.id
}

output "redis_security_group_id" {
  value = aws_security_group.redis.id
}

output "flow_log_group_name" {
  value = aws_cloudwatch_log_group.vpc_flow_logs.name
}
