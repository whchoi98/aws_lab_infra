output "vpc_id" {
  description = "VPC ID"
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
