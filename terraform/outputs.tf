output "vpc01_id" {
  description = "VPC01 ID"
  value       = module.vpc01.vpc_id
}

output "vpc02_id" {
  description = "VPC02 ID"
  value       = module.vpc02.vpc_id
}

output "dmz_vpc_id" {
  description = "DMZ VPC ID"
  value       = module.dmz_vpc.vpc_id
}

output "tgw_id" {
  description = "Transit Gateway ID"
  value       = module.tgw.tgw_id
}

output "aurora_endpoint" {
  description = "Aurora MySQL cluster endpoint"
  value       = module.data_services.aurora_endpoint
}

output "valkey_endpoint" {
  description = "ElastiCache Valkey endpoint"
  value       = module.data_services.valkey_endpoint
}

output "alb_dns" {
  description = "DMZ ALB DNS name"
  value       = module.dmz_vpc.alb_dns
}

output "cloudfront_url" {
  description = "CloudFront distribution URL"
  value       = module.dmz_vpc.cloudfront_url
}
