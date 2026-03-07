output "aurora_endpoint" {
  description = "Aurora MySQL cluster endpoint"
  value       = aws_rds_cluster.aurora.endpoint
}

output "aurora_reader_endpoint" {
  description = "Aurora MySQL cluster reader endpoint"
  value       = aws_rds_cluster.aurora.reader_endpoint
}

output "valkey_endpoint" {
  description = "ElastiCache Valkey primary endpoint"
  value       = aws_elasticache_replication_group.valkey.primary_endpoint_address
}

output "aurora_security_group_id" {
  description = "Aurora security group ID"
  value       = aws_security_group.aurora.id
}

output "valkey_security_group_id" {
  description = "Valkey security group ID"
  value       = aws_security_group.valkey.id
}
