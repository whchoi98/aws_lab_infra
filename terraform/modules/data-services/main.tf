# -------------------------------------------------------
# Aurora MySQL Cluster
# -------------------------------------------------------
resource "aws_db_subnet_group" "aurora" {
  name       = "lab-aurora-subnet-group"
  subnet_ids = var.data_subnet_ids

  tags = merge(var.common_tags, {
    Name = "Lab-Aurora-SubnetGroup"
  })
}

resource "aws_security_group" "aurora" {
  name_prefix = "lab-aurora-"
  description = "Security group for Aurora MySQL cluster"
  vpc_id      = var.vpc_id

  ingress {
    description = "MySQL from all VPCs"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = var.vpc_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "Lab-Aurora-SG"
  })
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier     = "lab-aurora-cluster"
  engine                 = "aurora-mysql"
  engine_version         = "8.0.mysql_aurora.3.07.1"
  database_name          = "labdb"
  master_username        = "admin"
  master_password        = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.aurora.name
  vpc_security_group_ids = [aws_security_group.aurora.id]
  skip_final_snapshot    = true
  storage_encrypted      = true

  tags = merge(var.common_tags, {
    Name = "Lab-Aurora-Cluster"
  })
}

resource "aws_rds_cluster_instance" "aurora" {
  count               = 2
  identifier          = "lab-aurora-instance-${count.index + 1}"
  cluster_identifier  = aws_rds_cluster.aurora.id
  instance_class      = "db.r6g.large"
  engine              = aws_rds_cluster.aurora.engine
  engine_version      = aws_rds_cluster.aurora.engine_version
  db_subnet_group_name = aws_db_subnet_group.aurora.name

  tags = merge(var.common_tags, {
    Name = "Lab-Aurora-Instance-${count.index + 1}"
  })
}

# -------------------------------------------------------
# ElastiCache Valkey (Redis-compatible)
# -------------------------------------------------------
resource "aws_elasticache_subnet_group" "valkey" {
  name       = "lab-valkey-subnet-group"
  subnet_ids = var.data_subnet_ids

  tags = merge(var.common_tags, {
    Name = "Lab-Valkey-SubnetGroup"
  })
}

resource "aws_security_group" "valkey" {
  name_prefix = "lab-valkey-"
  description = "Security group for ElastiCache Valkey"
  vpc_id      = var.vpc_id

  ingress {
    description = "Valkey from all VPCs"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = var.vpc_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "Lab-Valkey-SG"
  })
}

resource "aws_elasticache_replication_group" "valkey" {
  replication_group_id = "lab-valkey"
  description          = "Lab Valkey replication group"
  engine               = "valkey"
  engine_version       = "8.0"
  node_type            = "cache.r6g.large"
  num_cache_clusters   = 2
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.valkey.name
  security_group_ids   = [aws_security_group.valkey.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  automatic_failover_enabled = true

  tags = merge(var.common_tags, {
    Name = "Lab-Valkey"
  })
}
