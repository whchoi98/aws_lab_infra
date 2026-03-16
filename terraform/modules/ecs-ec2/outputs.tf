output "cluster_name" {
  description = "ECS EC2 cluster name"
  value       = aws_ecs_cluster.this.name
}

output "alb_dns_name" {
  description = "ALB DNS name"
  value       = aws_lb.this.dns_name
}

output "alb_sg_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb.id
}
