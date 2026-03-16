###############################################################################
# ECS EC2 Module - Graviton (t4g.large) with Base App
###############################################################################

data "aws_region" "current" {}

data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/arm64/recommended/image_id"
}

locals {
  cluster_name  = "lab-shop-ecs"
  namespace     = "lab-shop.local"
  instance_type = "t4g.large"

  services = {
    ui = {
      port = 8080
    }
    catalog = {
      port = 8080
    }
    carts = {
      port = 8080
    }
    checkout = {
      port = 8080
    }
    orders = {
      port = 8080
    }
  }
}

# -----------------------------------------------------------------------------
# ECS Cluster
# -----------------------------------------------------------------------------
resource "aws_ecs_cluster" "this" {
  name = local.cluster_name

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(var.common_tags, {
    Name = local.cluster_name
  })
}

# -----------------------------------------------------------------------------
# Capacity Provider (ASG)
# -----------------------------------------------------------------------------
resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name

  capacity_providers = [aws_ecs_capacity_provider.this.name]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = aws_ecs_capacity_provider.this.name
  }
}

resource "aws_ecs_capacity_provider" "this" {
  name = "${local.cluster_name}-cp"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.this.arn
    managed_termination_protection = "ENABLED"

    managed_scaling {
      maximum_scaling_step_size = 2
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 100
    }
  }

  tags = merge(var.common_tags, {
    Name = "${local.cluster_name}-cp"
  })
}

# -----------------------------------------------------------------------------
# Launch Template + ASG
# -----------------------------------------------------------------------------
resource "aws_iam_role" "ecs_instance" {
  name = "${local.cluster_name}-instance-role"

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
    Name = "${local.cluster_name}-instance-role"
  })
}

resource "aws_iam_role_policy_attachment" "ecs_instance" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ecs_instance_ssm" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ecs_instance" {
  name = "${local.cluster_name}-instance-profile"
  role = aws_iam_role.ecs_instance.name

  tags = merge(var.common_tags, {
    Name = "${local.cluster_name}-instance-profile"
  })
}

resource "aws_security_group" "ecs_instances" {
  name        = "${local.cluster_name}-instances-sg"
  description = "ECS EC2 instances security group"
  vpc_id      = var.vpc_id

  ingress {
    description     = "From ALB"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description = "Self-referencing for inter-service communication"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${local.cluster_name}-instances-sg"
  })
}

resource "aws_launch_template" "this" {
  name          = "${local.cluster_name}-lt"
  image_id      = data.aws_ssm_parameter.ecs_ami.value
  instance_type = local.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.ecs_instance.arn
  }

  vpc_security_group_ids = [aws_security_group.ecs_instances.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo "ECS_CLUSTER=${local.cluster_name}" >> /etc/ecs/ecs.config
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = merge(var.common_tags, {
      Name = "${local.cluster_name}-instance"
    })
  }

  tags = merge(var.common_tags, {
    Name = "${local.cluster_name}-lt"
  })
}

resource "aws_autoscaling_group" "this" {
  name                = "${local.cluster_name}-asg"
  desired_capacity    = 3
  min_size            = 1
  max_size            = 6
  vpc_zone_identifier = var.private_subnet_ids

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  protect_from_scale_in = true

  tag {
    key                 = "Name"
    value               = "${local.cluster_name}-instance"
    propagate_at_launch = true
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = var.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

# -----------------------------------------------------------------------------
# Cloud Map Namespace
# -----------------------------------------------------------------------------
resource "aws_service_discovery_private_dns_namespace" "this" {
  name        = local.namespace
  description = "Service discovery namespace for ECS EC2 lab shop"
  vpc         = var.vpc_id

  tags = merge(var.common_tags, {
    Name = local.namespace
  })
}

resource "aws_service_discovery_service" "services" {
  for_each = local.services

  name = each.key

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.this.id

    dns_records {
      ttl  = 10
      type = "SRV"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = merge(var.common_tags, {
    Name = "${local.cluster_name}-${each.key}"
  })
}

# -----------------------------------------------------------------------------
# CloudWatch Log Groups
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "services" {
  for_each = local.services

  name              = "/ecs/${local.cluster_name}/${each.key}"
  retention_in_days = 7

  tags = merge(var.common_tags, {
    Name = "/ecs/${local.cluster_name}/${each.key}"
  })
}

# -----------------------------------------------------------------------------
# IAM - Task Execution Role
# -----------------------------------------------------------------------------
resource "aws_iam_role" "task_execution" {
  name = "${local.cluster_name}-task-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${local.cluster_name}-task-execution"
  })
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# -----------------------------------------------------------------------------
# IAM - Task Role
# -----------------------------------------------------------------------------
resource "aws_iam_role" "task" {
  name = "${local.cluster_name}-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${local.cluster_name}-task"
  })
}

# -----------------------------------------------------------------------------
# Security Groups - ALB
# -----------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${local.cluster_name}-alb-sg"
  description = "ALB security group for ECS EC2"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${local.cluster_name}-alb-sg"
  })
}

# -----------------------------------------------------------------------------
# ALB
# -----------------------------------------------------------------------------
resource "aws_lb" "this" {
  name               = "${local.cluster_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  tags = merge(var.common_tags, {
    Name = "${local.cluster_name}-alb"
  })
}

resource "aws_lb_target_group" "ui" {
  name        = "${local.cluster_name}-ui-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/actuator/health"
    matcher             = "200"
  }

  tags = merge(var.common_tags, {
    Name = "${local.cluster_name}-ui-tg"
  })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ui.arn
  }

  tags = merge(var.common_tags, {
    Name = "${local.cluster_name}-listener"
  })
}

# -----------------------------------------------------------------------------
# Task Definitions (bridge network mode with links)
# -----------------------------------------------------------------------------

# UI (base retail store)
resource "aws_ecs_task_definition" "ui" {
  family             = "${local.cluster_name}-ui"
  network_mode       = "bridge"
  execution_role_arn = aws_iam_role.task_execution.arn
  task_role_arn      = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "ui"
      image     = "public.ecr.aws/aws-containers/retail-store-sample-ui:1.2.1"
      essential = true
      memory    = 512
      cpu       = 256
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 0
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "RETAIL_UI_ENDPOINTS_CATALOG", value = "http://catalog.${local.namespace}:8080" },
        { name = "RETAIL_UI_ENDPOINTS_CARTS", value = "http://carts.${local.namespace}:8080" },
        { name = "RETAIL_UI_ENDPOINTS_CHECKOUT", value = "http://checkout.${local.namespace}:8080" },
        { name = "RETAIL_UI_ENDPOINTS_ORDERS", value = "http://orders.${local.namespace}:8080" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.services["ui"].name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ui"
        }
      }
    }
  ])

  tags = merge(var.common_tags, {
    Name = "${local.cluster_name}-ui"
  })
}

# Catalog + MySQL sidecar
resource "aws_ecs_task_definition" "catalog" {
  family             = "${local.cluster_name}-catalog"
  network_mode       = "bridge"
  execution_role_arn = aws_iam_role.task_execution.arn
  task_role_arn      = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "catalog"
      image     = "public.ecr.aws/aws-containers/retail-store-sample-catalog:1.2.1"
      essential = true
      memory    = 512
      cpu       = 256
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 0
          protocol      = "tcp"
        }
      ]
      links = ["mysql"]
      environment = [
        { name = "DB_ENDPOINT", value = "mysql:3306" },
        { name = "DB_USER", value = "catalog" },
        { name = "DB_PASSWORD", value = "dYmNfWV4uEvTzoFu" },
        { name = "DB_NAME", value = "catalog" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.services["catalog"].name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "catalog"
        }
      }
    },
    {
      name      = "mysql"
      image     = "mysql:8.0"
      essential = true
      memory    = 512
      cpu       = 256
      portMappings = [
        {
          containerPort = 3306
          hostPort      = 0
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "MYSQL_ROOT_PASSWORD", value = "dYmNfWV4uEvTzoFu" },
        { name = "MYSQL_DATABASE", value = "catalog" },
        { name = "MYSQL_USER", value = "catalog" },
        { name = "MYSQL_PASSWORD", value = "dYmNfWV4uEvTzoFu" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.services["catalog"].name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "mysql"
        }
      }
    }
  ])

  tags = merge(var.common_tags, {
    Name = "${local.cluster_name}-catalog"
  })
}

# Carts + DynamoDB Local sidecar
resource "aws_ecs_task_definition" "carts" {
  family             = "${local.cluster_name}-carts"
  network_mode       = "bridge"
  execution_role_arn = aws_iam_role.task_execution.arn
  task_role_arn      = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "carts"
      image     = "public.ecr.aws/aws-containers/retail-store-sample-cart:1.2.1"
      essential = true
      memory    = 512
      cpu       = 256
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 0
          protocol      = "tcp"
        }
      ]
      links = ["dynamodb-local"]
      environment = [
        { name = "CARTS_DYNAMODB_ENDPOINT", value = "http://dynamodb-local:8000" },
        { name = "CARTS_DYNAMODB_CREATETABLE", value = "true" },
        { name = "AWS_ACCESS_KEY_ID", value = "key" },
        { name = "AWS_SECRET_ACCESS_KEY", value = "secret" },
        { name = "AWS_DEFAULT_REGION", value = "ap-northeast-2" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.services["carts"].name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "carts"
        }
      }
    },
    {
      name      = "dynamodb-local"
      image     = "amazon/dynamodb-local:2.0.0"
      essential = true
      memory    = 512
      cpu       = 256
      portMappings = [
        {
          containerPort = 8000
          hostPort      = 0
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.services["carts"].name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "dynamodb-local"
        }
      }
    }
  ])

  tags = merge(var.common_tags, {
    Name = "${local.cluster_name}-carts"
  })
}

# Checkout + Redis sidecar
resource "aws_ecs_task_definition" "checkout" {
  family             = "${local.cluster_name}-checkout"
  network_mode       = "bridge"
  execution_role_arn = aws_iam_role.task_execution.arn
  task_role_arn      = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "checkout"
      image     = "public.ecr.aws/aws-containers/retail-store-sample-checkout:1.2.1"
      essential = true
      memory    = 512
      cpu       = 256
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 0
          protocol      = "tcp"
        }
      ]
      links = ["redis"]
      environment = [
        { name = "REDIS_URL", value = "redis://redis:6379" },
        { name = "ENDPOINTS_ORDERS", value = "http://orders.${local.namespace}:8080" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.services["checkout"].name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "checkout"
        }
      }
    },
    {
      name      = "redis"
      image     = "redis:7-alpine"
      essential = true
      memory    = 256
      cpu       = 128
      portMappings = [
        {
          containerPort = 6379
          hostPort      = 0
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.services["checkout"].name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "redis"
        }
      }
    }
  ])

  tags = merge(var.common_tags, {
    Name = "${local.cluster_name}-checkout"
  })
}

# Orders + PostgreSQL sidecar
resource "aws_ecs_task_definition" "orders" {
  family             = "${local.cluster_name}-orders"
  network_mode       = "bridge"
  execution_role_arn = aws_iam_role.task_execution.arn
  task_role_arn      = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = "orders"
      image     = "public.ecr.aws/aws-containers/retail-store-sample-orders:1.2.1"
      essential = true
      memory    = 512
      cpu       = 256
      portMappings = [
        {
          containerPort = 8080
          hostPort      = 0
          protocol      = "tcp"
        }
      ]
      links = ["postgres"]
      environment = [
        { name = "SPRING_DATASOURCE_URL", value = "jdbc:postgresql://postgres:5432/orders" },
        { name = "SPRING_DATASOURCE_USERNAME", value = "orders" },
        { name = "SPRING_DATASOURCE_PASSWORD", value = "3z6sGLhGunfn0xZc" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.services["orders"].name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "orders"
        }
      }
    },
    {
      name      = "postgres"
      image     = "postgres:16-alpine"
      essential = true
      memory    = 512
      cpu       = 256
      portMappings = [
        {
          containerPort = 5432
          hostPort      = 0
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "POSTGRES_DB", value = "orders" },
        { name = "POSTGRES_USER", value = "orders" },
        { name = "POSTGRES_PASSWORD", value = "3z6sGLhGunfn0xZc" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.services["orders"].name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "postgres"
        }
      }
    }
  ])

  tags = merge(var.common_tags, {
    Name = "${local.cluster_name}-orders"
  })
}

# -----------------------------------------------------------------------------
# ECS Services
# -----------------------------------------------------------------------------
resource "aws_ecs_service" "ui" {
  name            = "ui"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.ui.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.this.name
    base              = 1
    weight            = 100
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ui.arn
    container_name   = "ui"
    container_port   = 8080
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.services["ui"].arn
    container_name = "ui"
    container_port = 8080
  }

  depends_on = [aws_lb_listener.http, aws_ecs_cluster_capacity_providers.this]

  tags = merge(var.common_tags, {
    Name = "${local.cluster_name}-ui"
  })
}

resource "aws_ecs_service" "catalog" {
  name            = "catalog"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.catalog.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.this.name
    base              = 1
    weight            = 100
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.services["catalog"].arn
    container_name = "catalog"
    container_port = 8080
  }

  depends_on = [aws_ecs_cluster_capacity_providers.this]

  tags = merge(var.common_tags, {
    Name = "${local.cluster_name}-catalog"
  })
}

resource "aws_ecs_service" "carts" {
  name            = "carts"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.carts.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.this.name
    base              = 1
    weight            = 100
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.services["carts"].arn
    container_name = "carts"
    container_port = 8080
  }

  depends_on = [aws_ecs_cluster_capacity_providers.this]

  tags = merge(var.common_tags, {
    Name = "${local.cluster_name}-carts"
  })
}

resource "aws_ecs_service" "checkout" {
  name            = "checkout"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.checkout.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.this.name
    base              = 1
    weight            = 100
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.services["checkout"].arn
    container_name = "checkout"
    container_port = 8080
  }

  depends_on = [aws_ecs_cluster_capacity_providers.this]

  tags = merge(var.common_tags, {
    Name = "${local.cluster_name}-checkout"
  })
}

resource "aws_ecs_service" "orders" {
  name            = "orders"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.orders.arn
  desired_count   = 1

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.this.name
    base              = 1
    weight            = 100
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.services["orders"].arn
    container_name = "orders"
    container_port = 8080
  }

  depends_on = [aws_ecs_cluster_capacity_providers.this]

  tags = merge(var.common_tags, {
    Name = "${local.cluster_name}-orders"
  })
}
