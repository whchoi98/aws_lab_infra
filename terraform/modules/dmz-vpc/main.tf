data "aws_region" "current" {}

locals {
  vpc_name = "DMZ-VPC"
}

# -------------------------------------------------------
# VPC
# -------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.common_tags, {
    Name = local.vpc_name
  })
}

# -------------------------------------------------------
# Internet Gateway
# -------------------------------------------------------
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-IGW"
  })
}

# -------------------------------------------------------
# Subnets - Public
# -------------------------------------------------------
resource "aws_subnet" "public" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-Public-${count.index == 0 ? "A" : "B"}"
    Tier = "Public"
  })
}

# -------------------------------------------------------
# Subnets - Private
# -------------------------------------------------------
resource "aws_subnet" "private" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-Private-${count.index == 0 ? "A" : "B"}"
    Tier = "Private"
  })
}

# -------------------------------------------------------
# Subnets - Data
# -------------------------------------------------------
resource "aws_subnet" "data" {
  count             = length(var.data_subnets)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.data_subnets[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-Data-${count.index == 0 ? "A" : "B"}"
    Tier = "Data"
  })
}

# -------------------------------------------------------
# Subnets - TGW Attach
# -------------------------------------------------------
resource "aws_subnet" "attach" {
  count             = length(var.attach_subnets)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.attach_subnets[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-Attach-${count.index == 0 ? "A" : "B"}"
    Tier = "Attach"
  })
}

# -------------------------------------------------------
# Subnets - Firewall
# -------------------------------------------------------
resource "aws_subnet" "fw" {
  count             = length(var.fw_subnets)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.fw_subnets[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-FW-${count.index == 0 ? "A" : "B"}"
    Tier = "Firewall"
  })
}

# -------------------------------------------------------
# Subnets - NAT Gateway
# -------------------------------------------------------
resource "aws_subnet" "natgw" {
  count             = length(var.natgw_subnets)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.natgw_subnets[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-NATGW-${count.index == 0 ? "A" : "B"}"
    Tier = "NATGW"
  })
}

# -------------------------------------------------------
# Subnets - ALB
# -------------------------------------------------------
resource "aws_subnet" "alb" {
  count                   = length(var.alb_subnets)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.alb_subnets[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-ALB-${count.index == 0 ? "A" : "B"}"
    Tier = "ALB"
  })
}

# -------------------------------------------------------
# Subnets - GWLB/Extra
# -------------------------------------------------------
resource "aws_subnet" "gwlb" {
  count             = length(var.gwlb_subnets)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.gwlb_subnets[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-GWLB-${count.index == 0 ? "A" : "B"}"
    Tier = "GWLB"
  })
}

# -------------------------------------------------------
# NAT Gateways (one per AZ)
# -------------------------------------------------------
resource "aws_eip" "natgw" {
  count  = 2
  domain = "vpc"

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-NATGW-EIP-${count.index == 0 ? "A" : "B"}"
  })
}

resource "aws_nat_gateway" "this" {
  count         = 2
  allocation_id = aws_eip.natgw[count.index].id
  subnet_id     = aws_subnet.natgw[count.index].id

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-NATGW-${count.index == 0 ? "A" : "B"}"
  })

  depends_on = [aws_internet_gateway.this]
}

# -------------------------------------------------------
# AWS Network Firewall
# -------------------------------------------------------
resource "aws_networkfirewall_rule_group" "stateless_drop_remote" {
  capacity = 100
  name     = "dmz-stateless-drop-remote"
  type     = "STATELESS"

  rule_group {
    rules_source {
      stateless_rules_and_custom_actions {
        stateless_rule {
          priority = 1
          rule_definition {
            actions = ["aws:forward_to_sfe"]
            match_attributes {
              protocols = [6]
              source {
                address_definition = "0.0.0.0/0"
              }
              destination {
                address_definition = "0.0.0.0/0"
              }
            }
          }
        }
      }
    }
  }

  tags = merge(var.common_tags, {
    Name = "dmz-stateless-drop-remote"
  })
}

resource "aws_networkfirewall_rule_group" "stateful_allow" {
  capacity = 100
  name     = "dmz-stateful-allow"
  type     = "STATEFUL"

  rule_group {
    rule_variables {
      ip_sets {
        key = "HOME_NET"
        ip_set {
          definition = [var.vpc_cidr, "10.1.0.0/16", "10.2.0.0/16"]
        }
      }
    }

    rules_source {
      rules_string = <<-RULES
        pass tcp $HOME_NET any -> any 80 (msg:"Allow HTTP outbound"; flow:to_server,established; sid:100001; rev:1;)
        pass tcp $HOME_NET any -> any 443 (msg:"Allow HTTPS outbound"; flow:to_server,established; sid:100002; rev:1;)
        pass tcp any 80 -> $HOME_NET any (msg:"Allow HTTP inbound"; flow:to_client,established; sid:100003; rev:1;)
        pass tcp any 443 -> $HOME_NET any (msg:"Allow HTTPS inbound"; flow:to_client,established; sid:100004; rev:1;)
        drop ip any any -> any any (msg:"Drop all other traffic"; sid:100099; rev:1;)
      RULES
    }
  }

  tags = merge(var.common_tags, {
    Name = "dmz-stateful-allow"
  })
}

resource "aws_networkfirewall_firewall_policy" "this" {
  name = "dmz-firewall-policy"

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:drop"]

    stateless_rule_group_reference {
      priority     = 1
      resource_arn = aws_networkfirewall_rule_group.stateless_drop_remote.arn
    }

    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.stateful_allow.arn
    }
  }

  tags = merge(var.common_tags, {
    Name = "dmz-firewall-policy"
  })
}

resource "aws_networkfirewall_firewall" "this" {
  name                = "dmz-network-firewall"
  firewall_policy_arn = aws_networkfirewall_firewall_policy.this.arn
  vpc_id              = aws_vpc.this.id

  dynamic "subnet_mapping" {
    for_each = aws_subnet.fw[*].id
    content {
      subnet_id = subnet_mapping.value
    }
  }

  tags = merge(var.common_tags, {
    Name = "dmz-network-firewall"
  })
}

# Extract firewall endpoint IDs per AZ
locals {
  fw_endpoint_map = {
    for s in aws_networkfirewall_firewall.this.firewall_status[0].sync_states :
    s.availability_zone => s.attachment[0].endpoint_id
  }
}

# -------------------------------------------------------
# Route Tables
# -------------------------------------------------------

# IGW Ingress Route Table (edge association)
resource "aws_route_table" "igw_ingress" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-IGW-Ingress-RT"
  })
}

resource "aws_route" "igw_ingress_to_public_a" {
  route_table_id         = aws_route_table.igw_ingress.id
  destination_cidr_block = var.public_subnets[0]
  vpc_endpoint_id        = local.fw_endpoint_map[var.azs[0]]
}

resource "aws_route" "igw_ingress_to_public_b" {
  route_table_id         = aws_route_table.igw_ingress.id
  destination_cidr_block = var.public_subnets[1]
  vpc_endpoint_id        = local.fw_endpoint_map[var.azs[1]]
}

resource "aws_route" "igw_ingress_to_alb_a" {
  route_table_id         = aws_route_table.igw_ingress.id
  destination_cidr_block = var.alb_subnets[0]
  vpc_endpoint_id        = local.fw_endpoint_map[var.azs[0]]
}

resource "aws_route" "igw_ingress_to_alb_b" {
  route_table_id         = aws_route_table.igw_ingress.id
  destination_cidr_block = var.alb_subnets[1]
  vpc_endpoint_id        = local.fw_endpoint_map[var.azs[1]]
}

resource "aws_route_table_association" "igw_ingress" {
  gateway_id     = aws_internet_gateway.this.id
  route_table_id = aws_route_table.igw_ingress.id
}

# Public Route Table - through NFW to IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-Public-RT"
  })
}

resource "aws_route" "public_default_a" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = local.fw_endpoint_map[var.azs[0]]
}

resource "aws_route_table_association" "public" {
  count          = length(var.public_subnets)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ALB Route Table
resource "aws_route_table" "alb" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-ALB-RT"
  })
}

resource "aws_route" "alb_default" {
  route_table_id         = aws_route_table.alb.id
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = local.fw_endpoint_map[var.azs[0]]
}

resource "aws_route_table_association" "alb" {
  count          = length(var.alb_subnets)
  subnet_id      = aws_subnet.alb[count.index].id
  route_table_id = aws_route_table.alb.id
}

# Firewall Route Tables (per AZ) - to IGW
resource "aws_route_table" "fw" {
  count  = 2
  vpc_id = aws_vpc.this.id

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-FW-RT-${count.index == 0 ? "A" : "B"}"
  })
}

resource "aws_route" "fw_default" {
  count                  = 2
  route_table_id         = aws_route_table.fw[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "fw" {
  count          = 2
  subnet_id      = aws_subnet.fw[count.index].id
  route_table_id = aws_route_table.fw[count.index].id
}

# NAT GW Route Tables (per AZ) - to NFW
resource "aws_route_table" "natgw" {
  count  = 2
  vpc_id = aws_vpc.this.id

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-NATGW-RT-${count.index == 0 ? "A" : "B"}"
  })
}

resource "aws_route" "natgw_default" {
  count                  = 2
  route_table_id         = aws_route_table.natgw[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "natgw" {
  count          = 2
  subnet_id      = aws_subnet.natgw[count.index].id
  route_table_id = aws_route_table.natgw[count.index].id
}

# Private Route Table - to NAT GW
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-Private-RT"
  })
}

resource "aws_route" "private_default" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnets)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Data Route Table - to NAT GW
resource "aws_route_table" "data" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-Data-RT"
  })
}

resource "aws_route" "data_default" {
  route_table_id         = aws_route_table.data.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[1].id
}

resource "aws_route_table_association" "data" {
  count          = length(var.data_subnets)
  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data.id
}

# Attach Route Table
resource "aws_route_table" "attach" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-Attach-RT"
  })
}

resource "aws_route_table_association" "attach" {
  count          = length(var.attach_subnets)
  subnet_id      = aws_subnet.attach[count.index].id
  route_table_id = aws_route_table.attach.id
}

# GWLB Route Table
resource "aws_route_table" "gwlb" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-GWLB-RT"
  })
}

resource "aws_route_table_association" "gwlb" {
  count          = length(var.gwlb_subnets)
  subnet_id      = aws_subnet.gwlb[count.index].id
  route_table_id = aws_route_table.gwlb.id
}

# -------------------------------------------------------
# SSM VPC Endpoints
# -------------------------------------------------------
resource "aws_security_group" "vpce" {
  name_prefix = "${local.vpc_name}-vpce-"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-VPCE-SG"
  })
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpce.id]

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-SSM-Endpoint"
  })
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpce.id]

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-SSMMessages-Endpoint"
  })
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.ec2messages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpce.id]

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-EC2Messages-Endpoint"
  })
}

# -------------------------------------------------------
# IAM Role for EC2 (SSM)
# -------------------------------------------------------
resource "aws_iam_role" "ec2_ssm" {
  name_prefix = "${local.vpc_name}-ec2-ssm-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-EC2-SSM-Role"
  })
}

resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name_prefix = "${local.vpc_name}-ec2-ssm-"
  role        = aws_iam_role.ec2_ssm.name

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-EC2-SSM-Profile"
  })
}

# -------------------------------------------------------
# Security Groups
# -------------------------------------------------------
resource "aws_security_group" "ec2" {
  name_prefix = "${local.vpc_name}-ec2-"
  description = "Security group for DMZ EC2 instances"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "HTTP from ALB"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "ICMP from RFC1918"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-EC2-SG"
  })
}

resource "aws_security_group" "alb" {
  name_prefix = "${local.vpc_name}-alb-"
  description = "Security group for DMZ ALB"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "HTTP from CloudFront"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [var.cloudfront_prefix_list_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-ALB-SG"
  })
}

# -------------------------------------------------------
# EC2 Instances in Private Subnets
# -------------------------------------------------------
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-*-arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "private" {
  count                  = length(var.private_subnets)
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t4g.medium"
  subnet_id              = aws_subnet.private[count.index].id
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm.name
  vpc_security_group_ids = [aws_security_group.ec2.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf install -y httpd
    systemctl enable httpd
    systemctl start httpd
    INSTANCE_ID=$(ec2-metadata -i | cut -d' ' -f2)
    echo "<h1>DMZ-VPC - Instance $INSTANCE_ID</h1><p>AZ: ${var.azs[count.index]}</p>" > /var/www/html/index.html
  EOF
  )

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-Private-Instance-${count.index == 0 ? "A" : "B"}"
  })
}

# -------------------------------------------------------
# Application Load Balancer
# -------------------------------------------------------
resource "aws_lb" "this" {
  name               = "dmz-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.alb[*].id

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-ALB"
  })
}

resource "aws_lb_target_group" "this" {
  name     = "dmz-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200"
  }

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-TG"
  })
}

resource "aws_lb_target_group_attachment" "this" {
  count            = length(var.private_subnets)
  target_group_arn = aws_lb_target_group.this.arn
  target_id        = aws_instance.private[count.index].id
  port             = 80
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-ALB-Listener"
  })
}

# -------------------------------------------------------
# CloudFront Distribution
# -------------------------------------------------------
resource "random_string" "cf_custom_header" {
  length  = 32
  special = false
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  comment             = "DMZ VPC CloudFront Distribution"
  default_root_object = "/"
  price_class         = "PriceClass_200"

  origin {
    domain_name = aws_lb.this.dns_name
    origin_id   = "dmz-alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-Custom-Header"
      value = random_string.cf_custom_header.result
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "dmz-alb"

    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = merge(var.common_tags, {
    Name = "${local.vpc_name}-CloudFront"
  })
}
