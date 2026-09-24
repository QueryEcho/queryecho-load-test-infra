data "aws_region" "current" {}

resource "random_password" "collector_api_key" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "collector_api_key" {
  name                    = "${var.name_prefix}/collector-ingest-api-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "collector_api_key" {
  secret_id     = aws_secretsmanager_secret.collector_api_key.id
  secret_string = jsonencode({ apiKey = random_password.collector_api_key.result })
}

resource "aws_ecs_cluster" "this" {
  name = "${var.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

resource "aws_cloudwatch_log_group" "service" {
  for_each = toset(["spring", "java", "collector"])

  name              = "/queryecho/${var.name_prefix}/${each.key}"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name_prefix}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "secrets" {
  statement {
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      var.mysql_secret_arn,
      var.postgres_secret_arn,
      aws_secretsmanager_secret.collector_api_key.arn
    ]
  }
}

resource "aws_iam_role_policy" "secrets" {
  name   = "read-runtime-secrets"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.secrets.json
}

resource "aws_iam_role" "task" {
  name               = "${var.name_prefix}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

data "aws_iam_policy_document" "ecs_exec" {
  statement {
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ecs_exec" {
  name   = "allow-ecs-exec-channels"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.ecs_exec.json
}

resource "aws_lb" "targets" {
  name               = "${substr(var.name_prefix, 0, 20)}-targets"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [var.target_alb_security_group]
  subnets            = var.private_subnet_ids
}

resource "aws_lb" "collector" {
  name               = "${substr(var.name_prefix, 0, 18)}-collector"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [var.collector_alb_security_group]
  subnets            = var.private_subnet_ids
}

resource "aws_lb_target_group" "spring" {
  name                 = "${substr(var.name_prefix, 0, 18)}-spring"
  port                 = 8080
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = data.aws_vpc.selected.id
  deregistration_delay = 10

  health_check {
    path                = "/health"
    matcher             = "200-399"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }
}

resource "aws_lb_target_group" "java" {
  name                 = "${substr(var.name_prefix, 0, 20)}-java"
  port                 = 8080
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = data.aws_vpc.selected.id
  deregistration_delay = 10

  health_check {
    path                = "/health"
    matcher             = "200-399"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }
}

resource "aws_lb_target_group" "collector" {
  name                 = "${substr(var.name_prefix, 0, 15)}-collector"
  port                 = 8080
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = data.aws_vpc.selected.id
  deregistration_delay = 10

  health_check {
    path                = "/actuator/health"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }
}

data "aws_vpc" "selected" {
  id = data.aws_subnet.selected.vpc_id
}

data "aws_subnet" "selected" {
  id = var.private_subnet_ids[0]
}

resource "aws_lb_listener" "spring" {
  load_balancer_arn = aws_lb.targets.arn
  port              = 8081
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.spring.arn
  }
}

resource "aws_lb_listener" "java" {
  load_balancer_arn = aws_lb.targets.arn
  port              = 8082
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.java.arn
  }
}

resource "aws_lb_listener" "collector" {
  load_balancer_arn = aws_lb.collector.arn
  port              = 8080
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.collector.arn
  }
}

locals {
  collector_url = "http://${aws_lb.collector.dns_name}:8080"

  common_log_options = {
    awslogs-region        = data.aws_region.current.region
    awslogs-stream-prefix = "ecs"
  }
}

resource "aws_ecs_task_definition" "spring" {
  family                   = "${var.name_prefix}-spring"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.target_cpu)
  memory                   = tostring(var.target_memory)
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name         = "spring-target"
    image        = var.spring_image
    essential    = true
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]
    environment = [
      { name = "SERVER_PORT", value = "8080" },
      { name = "SPRING_DATASOURCE_URL", value = "jdbc:mysql://${var.mysql_host}:${var.mysql_port}/${var.mysql_database}?useSSL=false&allowPublicKeyRetrieval=true&rewriteBatchedStatements=true" },
      { name = "SPRING_DATASOURCE_USERNAME", value = var.mysql_username },
      { name = "QUERYECHO_SDK_ENABLED", value = "true" },
      { name = "QUERYECHO_SDK_TRANSPORT", value = "HTTP" },
      { name = "QUERYECHO_SDK_COLLECTOR_URL", value = local.collector_url },
      { name = "QUERYECHO_SDK_APP_NAME", value = "spring-load-target" },
      { name = "QUERYECHO_SDK_ENVIRONMENT", value = "loadtest" },
      { name = "QUERYECHO_SDK_INSTANCE_ID", value = "spring-ecs" },
      { name = "QUERYECHO_SDK_DB_TYPE", value = "mysql" }
    ]
    secrets = [
      { name = "SPRING_DATASOURCE_PASSWORD", valueFrom = "${var.mysql_secret_arn}:password::" },
      { name = "QUERYECHO_INGEST_API_KEY", valueFrom = "${aws_secretsmanager_secret.collector_api_key.arn}:apiKey::" },
      { name = "QUERYECHO_SDK_API_KEY", valueFrom = "${aws_secretsmanager_secret.collector_api_key.arn}:apiKey::" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = merge(local.common_log_options, {
        awslogs-group = aws_cloudwatch_log_group.service["spring"].name
      })
    }
  }])
}

resource "aws_ecs_task_definition" "java" {
  family                   = "${var.name_prefix}-java"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.target_cpu)
  memory                   = tostring(var.target_memory)
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name         = "java-target"
    image        = var.java_image
    essential    = true
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]
    environment = [
      { name = "APP_PORT", value = "8080" },
      { name = "DB_URL", value = "jdbc:mysql://${var.mysql_host}:${var.mysql_port}/${var.mysql_database}?useSSL=false&allowPublicKeyRetrieval=true" },
      { name = "DB_USERNAME", value = var.mysql_username },
      { name = "QUERYECHO_COLLECTOR_URL", value = local.collector_url },
      { name = "QUERYECHO_APP_NAME", value = "java-load-target" },
      { name = "QUERYECHO_ENVIRONMENT", value = "loadtest" },
      { name = "QUERYECHO_INSTANCE_ID", value = "java-ecs" },
      { name = "QUERYECHO_DB_TYPE", value = "mysql" }
    ]
    secrets = [
      { name = "DB_PASSWORD", valueFrom = "${var.mysql_secret_arn}:password::" },
      { name = "QUERYECHO_INGEST_API_KEY", valueFrom = "${aws_secretsmanager_secret.collector_api_key.arn}:apiKey::" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = merge(local.common_log_options, {
        awslogs-group = aws_cloudwatch_log_group.service["java"].name
      })
    }
  }])
}

resource "aws_ecs_task_definition" "collector" {
  family                   = "${var.name_prefix}-collector"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.collector_cpu)
  memory                   = tostring(var.collector_memory)
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name         = "queryecho"
    image        = var.collector_image
    essential    = true
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]
    environment = [
      { name = "QUERYECHO_DB_URL", value = "jdbc:postgresql://${var.postgres_host}:${var.postgres_port}/${var.postgres_database}?reWriteBatchedInserts=true" },
      { name = "QUERYECHO_DB_USERNAME", value = var.postgres_username },
      { name = "QUERYECHO_DEMO_ENABLED", value = "false" },
      { name = "QUERYECHO_SDK_ENABLED", value = "false" }
    ]
    secrets = [
      { name = "QUERYECHO_DB_PASSWORD", valueFrom = "${var.postgres_secret_arn}:password::" },
      { name = "QUERYECHO_INGEST_API_KEY", valueFrom = "${aws_secretsmanager_secret.collector_api_key.arn}:apiKey::" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = merge(local.common_log_options, {
        awslogs-group = aws_cloudwatch_log_group.service["collector"].name
      })
    }
  }])
}

resource "aws_ecs_service" "spring" {
  name            = "${var.name_prefix}-spring"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.spring.arn
  desired_count   = var.spring_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.target_task_security_group]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.spring.arn
    container_name   = "spring-target"
    container_port   = 8080
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  enable_execute_command = true
  depends_on             = [aws_lb_listener.spring]
}

resource "aws_ecs_service" "java" {
  name            = "${var.name_prefix}-java"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.java.arn
  desired_count   = var.java_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.target_task_security_group]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.java.arn
    container_name   = "java-target"
    container_port   = 8080
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  enable_execute_command = true
  depends_on             = [aws_lb_listener.java]
}

resource "aws_ecs_service" "collector" {
  name            = "${var.name_prefix}-collector"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.collector.arn
  desired_count   = var.collector_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.collector_task_security_group]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.collector.arn
    container_name   = "queryecho"
    container_port   = 8080
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  enable_execute_command = true
  depends_on             = [aws_lb_listener.collector]
}
