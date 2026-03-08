data "aws_region" "current" {}

# -------------------------------------------------------
# VPC
# -------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.common_tags, {
    Name = "lab-${lower(var.vpc_name)}"
  })
}

# -------------------------------------------------------
# Subnets - Public
# -------------------------------------------------------
resource "aws_subnet" "public" {
  count             = length(var.public_subnets)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.public_subnets[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.common_tags, {
    Name = "lab-${lower(var.vpc_name)}-public-subnet-${count.index == 0 ? "a" : "b"}"
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
    Name = "lab-${lower(var.vpc_name)}-private-subnet-${count.index == 0 ? "a" : "b"}"
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
    Name = "lab-${lower(var.vpc_name)}-data-subnet-${count.index == 0 ? "a" : "b"}"
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
    Name = "lab-${lower(var.vpc_name)}-attach-subnet-${count.index == 0 ? "a" : "b"}"
    Tier = "Attach"
  })
}

# -------------------------------------------------------
# Route Tables
# -------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.common_tags, {
    Name = "lab-${lower(var.vpc_name)}-public-rt"
  })
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.common_tags, {
    Name = "lab-${lower(var.vpc_name)}-private-rt"
  })
}

resource "aws_route_table" "data" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.common_tags, {
    Name = "lab-${lower(var.vpc_name)}-data-rt"
  })
}

resource "aws_route_table" "attach" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.common_tags, {
    Name = "lab-${lower(var.vpc_name)}-attach-rt"
  })
}

# -------------------------------------------------------
# Route Table Associations
# -------------------------------------------------------
resource "aws_route_table_association" "public" {
  count          = length(var.public_subnets)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnets)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "data" {
  count          = length(var.data_subnets)
  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data.id
}

resource "aws_route_table_association" "attach" {
  count          = length(var.attach_subnets)
  subnet_id      = aws_subnet.attach[count.index].id
  route_table_id = aws_route_table.attach.id
}

# -------------------------------------------------------
# SSM VPC Endpoints
# -------------------------------------------------------
resource "aws_security_group" "vpce" {
  name_prefix = "${var.vpc_name}-vpce-"
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
    Name = "lab-${lower(var.vpc_name)}-vpce-sg"
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
    Name = "lab-${lower(var.vpc_name)}-ssm-endpoint"
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
    Name = "lab-${lower(var.vpc_name)}-ssmmessages-endpoint"
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
    Name = "lab-${lower(var.vpc_name)}-ec2messages-endpoint"
  })
}

# -------------------------------------------------------
# IAM Role for EC2 (SSM)
# -------------------------------------------------------
resource "aws_iam_role" "ec2_ssm" {
  name_prefix = "${var.vpc_name}-ec2-ssm-"

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
    Name = "lab-${lower(var.vpc_name)}-ec2-ssm-role"
  })
}

resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name_prefix = "${var.vpc_name}-ec2-ssm-"
  role        = aws_iam_role.ec2_ssm.name

  tags = merge(var.common_tags, {
    Name = "lab-${lower(var.vpc_name)}-ec2-ssm-profile"
  })
}

# -------------------------------------------------------
# Security Group for EC2 Instances
# -------------------------------------------------------
resource "aws_security_group" "ec2" {
  name_prefix = "${var.vpc_name}-ec2-"
  description = "Security group for EC2 instances"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP from all VPCs"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
  }

  ingress {
    description = "HTTPS from all VPCs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/8"]
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
    Name = "lab-${lower(var.vpc_name)}-ec2-sg"
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
  count                = length(var.private_subnets) * 2
  ami                  = data.aws_ami.amazon_linux_2023.id
  instance_type        = "t4g.large"
  subnet_id            = aws_subnet.private[count.index % length(var.private_subnets)].id
  iam_instance_profile = aws_iam_instance_profile.ec2_ssm.name
  vpc_security_group_ids = [aws_security_group.ec2.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    # SSM Agent install (if not present)
    if ! systemctl list-unit-files | grep -q amazon-ssm-agent; then
      dnf install -y amazon-ssm-agent
    fi
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
    # httpd install
    dnf install -y httpd
    systemctl enable httpd
    systemctl start httpd
    INSTANCE_ID=$(ec2-metadata -i | cut -d' ' -f2)
    AZ=$(ec2-metadata -z | cut -d' ' -f2)
    echo "<h1>${var.vpc_name} - Instance $INSTANCE_ID</h1><p>AZ: $AZ</p><p>IP: $(hostname -I)</p>" > /var/www/html/index.html
    # SSM Agent restart after httpd install
    systemctl restart amazon-ssm-agent
  EOF
  )

  tags = merge(var.common_tags, {
    Name = "lab-${lower(var.vpc_name)}-private-ec2-${count.index % 2 == 0 ? "a" : "b"}${format("%02d", floor(count.index / 2) + 1)}"
  })
}
