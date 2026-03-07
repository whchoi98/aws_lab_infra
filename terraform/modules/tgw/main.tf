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
    Name = "Lab-TGW"
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
    Name = "TGW-Attach-VPC01"
  })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "vpc02" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = var.vpc02_id
  subnet_ids         = var.vpc02_attach_subnets

  transit_gateway_default_route_table_association = true
  transit_gateway_default_route_table_propagation = true

  tags = merge(var.common_tags, {
    Name = "TGW-Attach-VPC02"
  })
}

resource "aws_ec2_transit_gateway_vpc_attachment" "dmz" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = var.dmz_vpc_id
  subnet_ids         = var.dmz_attach_subnets

  transit_gateway_default_route_table_association = true
  transit_gateway_default_route_table_propagation = true

  tags = merge(var.common_tags, {
    Name = "TGW-Attach-DMZ"
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
