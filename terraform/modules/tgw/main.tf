# -------------------------------------------------------
# Transit Gateway
# -------------------------------------------------------
resource "aws_ec2_transit_gateway" "this" {
  description                     = "Lab Transit Gateway"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"
  auto_accept_shared_attachments  = "enable"

  tags = merge(var.common_tags, {
    Name = "lab-tgw"
  })
}

# -------------------------------------------------------
# VPC Attachments
# -------------------------------------------------------
resource "aws_ec2_transit_gateway_vpc_attachment" "vpc01" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = var.vpc01_id
  subnet_ids         = var.vpc01_attach_subnets

  transit_gateway_default_route_table_association = true
  transit_gateway_default_route_table_propagation = true

  tags = merge(var.common_tags, {
    Name = "lab-tgw-vpc01-attach"
  })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "vpc02" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = var.vpc02_id
  subnet_ids         = var.vpc02_attach_subnets

  transit_gateway_default_route_table_association = true
  transit_gateway_default_route_table_propagation = true

  tags = merge(var.common_tags, {
    Name = "lab-tgw-vpc02-attach"
  })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "dmz" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = var.dmz_vpc_id
  subnet_ids         = var.dmz_attach_subnets

  transit_gateway_default_route_table_association = true
  transit_gateway_default_route_table_propagation = true

  tags = merge(var.common_tags, {
    Name = "lab-tgw-dmzvpc-attach"
  })
}

# -------------------------------------------------------
# VPC01 Routes via TGW
# -------------------------------------------------------

# VPC01 -> VPC02
resource "aws_route" "vpc01_public_to_vpc02" {
  route_table_id         = var.vpc01_public_rt_id
  destination_cidr_block = var.vpc02_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.vpc01]
}

resource "aws_route" "vpc01_private_to_vpc02" {
  route_table_id         = var.vpc01_private_rt_id
  destination_cidr_block = var.vpc02_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.vpc01]
}

resource "aws_route" "vpc01_data_to_vpc02" {
  route_table_id         = var.vpc01_data_rt_id
  destination_cidr_block = var.vpc02_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.vpc01]
}

# VPC01 -> DMZ
resource "aws_route" "vpc01_public_to_dmz" {
  route_table_id         = var.vpc01_public_rt_id
  destination_cidr_block = var.dmz_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.vpc01]
}

resource "aws_route" "vpc01_private_to_dmz" {
  route_table_id         = var.vpc01_private_rt_id
  destination_cidr_block = var.dmz_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.vpc01]
}

resource "aws_route" "vpc01_data_to_dmz" {
  route_table_id         = var.vpc01_data_rt_id
  destination_cidr_block = var.dmz_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.vpc01]
}

# VPC01 default route via TGW (for internet via DMZ)
resource "aws_route" "vpc01_private_default" {
  route_table_id         = var.vpc01_private_rt_id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.vpc01]
}

resource "aws_route" "vpc01_data_default" {
  route_table_id         = var.vpc01_data_rt_id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.vpc01]
}

# -------------------------------------------------------
# VPC02 Routes via TGW
# -------------------------------------------------------

# VPC02 -> VPC01
resource "aws_route" "vpc02_public_to_vpc01" {
  route_table_id         = var.vpc02_public_rt_id
  destination_cidr_block = var.vpc01_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.vpc02]
}

resource "aws_route" "vpc02_private_to_vpc01" {
  route_table_id         = var.vpc02_private_rt_id
  destination_cidr_block = var.vpc01_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.vpc02]
}

resource "aws_route" "vpc02_data_to_vpc01" {
  route_table_id         = var.vpc02_data_rt_id
  destination_cidr_block = var.vpc01_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.vpc02]
}

# VPC02 -> DMZ
resource "aws_route" "vpc02_public_to_dmz" {
  route_table_id         = var.vpc02_public_rt_id
  destination_cidr_block = var.dmz_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.vpc02]
}

resource "aws_route" "vpc02_private_to_dmz" {
  route_table_id         = var.vpc02_private_rt_id
  destination_cidr_block = var.dmz_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.vpc02]
}

resource "aws_route" "vpc02_data_to_dmz" {
  route_table_id         = var.vpc02_data_rt_id
  destination_cidr_block = var.dmz_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.vpc02]
}

# VPC02 default route via TGW (for internet via DMZ)
resource "aws_route" "vpc02_private_default" {
  route_table_id         = var.vpc02_private_rt_id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.vpc02]
}

resource "aws_route" "vpc02_data_default" {
  route_table_id         = var.vpc02_data_rt_id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.vpc02]
}

# -------------------------------------------------------
# DMZ VPC Routes via TGW
# -------------------------------------------------------

# DMZ -> VPC01
resource "aws_route" "dmz_private_to_vpc01" {
  route_table_id         = var.dmz_private_rt_id
  destination_cidr_block = var.vpc01_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.dmz]
}

resource "aws_route" "dmz_data_to_vpc01" {
  route_table_id         = var.dmz_data_rt_id
  destination_cidr_block = var.vpc01_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.dmz]
}

# DMZ -> VPC02
resource "aws_route" "dmz_private_to_vpc02" {
  route_table_id         = var.dmz_private_rt_id
  destination_cidr_block = var.vpc02_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.dmz]
}

resource "aws_route" "dmz_data_to_vpc02" {
  route_table_id         = var.dmz_data_rt_id
  destination_cidr_block = var.vpc02_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.dmz]
}

# DMZ Attach -> VPC01/VPC02
resource "aws_route" "dmz_attach_to_vpc01" {
  route_table_id         = var.dmz_attach_rt_id
  destination_cidr_block = var.vpc01_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.dmz]
}

resource "aws_route" "dmz_attach_to_vpc02" {
  route_table_id         = var.dmz_attach_rt_id
  destination_cidr_block = var.vpc02_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.dmz]
}

# -------------------------------------------------------
# DMZ NATGW Subnet return routes (VPC01/VPC02 CIDRs → TGW)
# -------------------------------------------------------
resource "aws_route" "dmz_natgw_to_vpc01" {
  count                  = length(var.dmz_natgw_rt_ids)
  route_table_id         = var.dmz_natgw_rt_ids[count.index]
  destination_cidr_block = var.vpc01_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.dmz]
}

resource "aws_route" "dmz_natgw_to_vpc02" {
  count                  = length(var.dmz_natgw_rt_ids)
  route_table_id         = var.dmz_natgw_rt_ids[count.index]
  destination_cidr_block = var.vpc02_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.dmz]
}

# -------------------------------------------------------
# TGW Default Route: 0.0.0.0/0 → DMZ VPC attachment
# -------------------------------------------------------
resource "aws_ec2_transit_gateway_route" "default_to_dmz" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.dmz.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.this.association_default_route_table_id
}
