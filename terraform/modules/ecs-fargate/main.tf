###############################################################################
# ECS Fargate Module - ARM64 with Bilingual App
###############################################################################

data "aws_region" "current" {}

locals {
  cluster_name = "lab-shop-ecs-fargate"
  namespace    = "lab-shop-fg.local"

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
# Cloud Map Namespace
# -----------------------------------------------------------------------------
resource "aws_service_discovery_private_dns_namespace" "this" {
  name        = local.namespace
  description = "Service discovery namespace for ECS Fargate lab shop"
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
      type = "A"
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
# Security Groups
# -----------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${local.cluster_name}-alb-sg"
  description = "ALB security group for ECS Fargate"
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

resource "aws_security_group" "tasks" {
  name        = "${local.cluster_name}-tasks-sg"
  description = "ECS tasks security group"
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
    Name = "${local.cluster_name}-tasks-sg"
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
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
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
# Task Definitions
# -----------------------------------------------------------------------------

# UI (bilingual)
resource "aws_ecs_task_definition" "ui" {
  family                   = "${local.cluster_name}-ui"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name      = "ui"
      image     = var.bilingual_ecr_uri
      essential = true
      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "ENDPOINTS_CATALOG", value = "http://catalog.${local.namespace}:8080" },
        { name = "ENDPOINTS_CARTS", value = "http://carts.${local.namespace}:8080" },
        { name = "ENDPOINTS_CHECKOUT", value = "http://checkout.${local.namespace}:8080" },
        { name = "ENDPOINTS_ORDERS", value = "http://orders.${local.namespace}:8080" }
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
  family                   = "${local.cluster_name}-catalog"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name      = "catalog"
      image     = "public.ecr.aws/aws-containers/retail-store-sample-catalog:1.2.1"
      essential = true
      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "DB_ENDPOINT", value = "localhost:3306" },
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
      portMappings = [
        {
          containerPort = 3306
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
  family                   = "${local.cluster_name}-carts"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name      = "carts"
      image     = "public.ecr.aws/aws-containers/retail-store-sample-cart:1.2.1"
      essential = true
      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "CARTS_DYNAMODB_ENDPOINT", value = "http://localhost:8000" },
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
      portMappings = [
        {
          containerPort = 8000
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
  family                   = "${local.cluster_name}-checkout"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name      = "checkout"
      image     = "public.ecr.aws/aws-containers/retail-store-sample-checkout:1.2.1"
      essential = true
      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "REDIS_URL", value = "redis://localhost:6379" },
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
      portMappings = [
        {
          containerPort = 6379
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
  family                   = "${local.cluster_name}-orders"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "ARM64"
  }

  container_definitions = jsonencode([
    {
      name      = "orders"
      image     = "public.ecr.aws/aws-containers/retail-store-sample-orders:1.2.1"
      essential = true
      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]
      environment = [
        { name = "SPRING_DATASOURCE_URL", value = "jdbc:postgresql://localhost:5432/orders" },
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
      portMappings = [
        {
          containerPort = 5432
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
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.ui.arn
    container_name   = "ui"
    container_port   = 8080
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["ui"].arn
  }

  depends_on = [aws_lb_listener.http]

  tags = merge(var.common_tags, {
    Name = "${local.cluster_name}-ui"
  })
}

resource "aws_ecs_service" "catalog" {
  name            = "catalog"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.catalog.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["catalog"].arn
  }

  tags = merge(var.common_tags, {
    Name = "${local.cluster_name}-catalog"
  })
}

resource "aws_ecs_service" "carts" {
  name            = "carts"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.carts.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["carts"].arn
  }

  tags = merge(var.common_tags, {
    Name = "${local.cluster_name}-carts"
  })
}

resource "aws_ecs_service" "checkout" {
  name            = "checkout"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.checkout.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["checkout"].arn
  }

  tags = merge(var.common_tags, {
    Name = "${local.cluster_name}-checkout"
  })
}

resource "aws_ecs_service" "orders" {
  name            = "orders"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.orders.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.tasks.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.services["orders"].arn
  }

  tags = merge(var.common_tags, {
    Name = "${local.cluster_name}-orders"
  })
}
