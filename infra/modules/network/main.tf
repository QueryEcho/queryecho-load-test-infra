data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-igw" }
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.this.id
  availability_zone       = local.azs[count.index]
  cidr_block              = var.public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.name_prefix}-public-${count.index + 1}" }
}

resource "aws_subnet" "app" {
  count = 2

  vpc_id            = aws_vpc.this.id
  availability_zone = local.azs[count.index]
  cidr_block        = var.app_subnet_cidrs[count.index]
  tags              = { Name = "${var.name_prefix}-app-${count.index + 1}" }
}

resource "aws_subnet" "db" {
  count = 2

  vpc_id            = aws_vpc.this.id
  availability_zone = local.azs[count.index]
  cidr_block        = var.db_subnet_cidrs[count.index]
  tags              = { Name = "${var.name_prefix}-db-${count.index + 1}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "${var.name_prefix}-public-rt" }
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.name_prefix}-nat-eip" }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "${var.name_prefix}-nat" }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "app" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }
  tags = { Name = "${var.name_prefix}-app-rt" }
}

resource "aws_route_table_association" "app" {
  count = 2

  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app.id
}

resource "aws_route_table" "db" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name_prefix}-db-rt" }
}

resource "aws_route_table_association" "db" {
  count = 2

  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db.id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.app.id]
  tags              = { Name = "${var.name_prefix}-s3-endpoint" }
}

data "aws_region" "current" {}

locals {
  security_groups = toset([
    "lambda", "target-alb", "target-task", "collector-alb", "collector-task", "mysql", "postgres"
  ])
}

resource "aws_security_group" "this" {
  for_each = local.security_groups

  name_prefix = "${var.name_prefix}-${each.key}-"
  description = "${each.key} security group for QueryEcho load test"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name_prefix}-${each.key}" }

  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_egress_rule" "all" {
  for_each = aws_security_group.this

  security_group_id = each.value.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "lambda_to_spring_alb" {
  security_group_id            = aws_security_group.this["target-alb"].id
  referenced_security_group_id = aws_security_group.this["lambda"].id
  from_port                    = 8081
  to_port                      = 8081
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "lambda_to_java_alb" {
  security_group_id            = aws_security_group.this["target-alb"].id
  referenced_security_group_id = aws_security_group.this["lambda"].id
  from_port                    = 8082
  to_port                      = 8082
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "target_alb_to_tasks" {
  security_group_id            = aws_security_group.this["target-task"].id
  referenced_security_group_id = aws_security_group.this["target-alb"].id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "targets_to_collector_alb" {
  security_group_id            = aws_security_group.this["collector-alb"].id
  referenced_security_group_id = aws_security_group.this["target-task"].id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "lambda_to_collector_alb" {
  security_group_id            = aws_security_group.this["collector-alb"].id
  referenced_security_group_id = aws_security_group.this["lambda"].id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "collector_alb_to_task" {
  security_group_id            = aws_security_group.this["collector-task"].id
  referenced_security_group_id = aws_security_group.this["collector-alb"].id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "targets_to_mysql" {
  security_group_id            = aws_security_group.this["mysql"].id
  referenced_security_group_id = aws_security_group.this["target-task"].id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "collector_to_postgres" {
  security_group_id            = aws_security_group.this["postgres"].id
  referenced_security_group_id = aws_security_group.this["collector-task"].id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}
