output "tgw_id" {
  description = "Transit Gateway ID"
  value       = aws_ec2_transit_gateway.this.id
}

output "vpc01_attachment_id" {
  description = "VPC01 TGW attachment ID"
  value       = aws_ec2_transit_gateway_vpc_attachment.vpc01.id
}

output "vpc02_attachment_id" {
  description = "VPC02 TGW attachment ID"
  value       = aws_ec2_transit_gateway_vpc_attachment.vpc02.id
}

output "dmz_attachment_id" {
  description = "DMZ VPC TGW attachment ID"
  value       = aws_ec2_transit_gateway_vpc_attachment.dmz.id
}
