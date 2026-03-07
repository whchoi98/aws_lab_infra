output "vpc_id" {
  description = "DMZ VPC ID"
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "data_subnet_ids" {
  description = "Data subnet IDs"
  value       = aws_subnet.data[*].id
}

output "attach_subnet_ids" {
  description = "TGW Attach subnet IDs"
  value       = aws_subnet.attach[*].id
}

output "fw_subnet_ids" {
  description = "Firewall subnet IDs"
  value       = aws_subnet.fw[*].id
}

output "natgw_subnet_ids" {
  description = "NAT Gateway subnet IDs"
  value       = aws_subnet.natgw[*].id
}

output "alb_subnet_ids" {
  description = "ALB subnet IDs"
  value       = aws_subnet.alb[*].id
}

output "gwlb_subnet_ids" {
  description = "GWLB subnet IDs"
  value       = aws_subnet.gwlb[*].id
}

output "public_route_table_id" {
  description = "Public route table ID"
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "Private route table ID"
  value       = aws_route_table.private.id
}

output "data_route_table_id" {
  description = "Data route table ID"
  value       = aws_route_table.data.id
}

output "attach_route_table_id" {
  description = "Attach route table ID"
  value       = aws_route_table.attach.id
}

output "fw_route_table_ids" {
  description = "Firewall route table IDs (per AZ)"
  value       = aws_route_table.fw[*].id
}

output "natgw_route_table_ids" {
  description = "NAT GW route table IDs (per AZ)"
  value       = aws_route_table.natgw[*].id
}

output "igw_route_table_id" {
  description = "IGW ingress route table ID"
  value       = aws_route_table.igw_ingress.id
}

output "alb_dns" {
  description = "ALB DNS name"
  value       = aws_lb.this.dns_name
}

output "cloudfront_url" {
  description = "CloudFront distribution domain name"
  value       = "https://${aws_cloudfront_distribution.this.domain_name}"
}
