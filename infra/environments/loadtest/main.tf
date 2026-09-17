locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

module "network" {
  source = "../../modules/network"

  name_prefix = local.name_prefix
  vpc_cidr    = var.vpc_cidr
}

module "registry" {
  source = "../../modules/registry"

  name_prefix = local.name_prefix
}

module "databases" {
  source = "../../modules/databases"

  name_prefix             = local.name_prefix
  db_subnet_ids           = module.network.db_subnet_ids
  mysql_security_group    = module.network.mysql_security_group_id
  postgres_security_group = module.network.postgres_security_group_id
  mysql_instance_class    = var.mysql_instance_class
  postgres_instance_class = var.postgres_instance_class
}

module "applications" {
  source = "../../modules/applications"

  name_prefix                   = local.name_prefix
  private_subnet_ids            = module.network.app_subnet_ids
  target_alb_security_group     = module.network.target_alb_security_group_id
  target_task_security_group    = module.network.target_task_security_group_id
  collector_alb_security_group  = module.network.collector_alb_security_group_id
  collector_task_security_group = module.network.collector_task_security_group_id

  spring_image    = "${module.registry.repository_urls["spring-target"]}:${var.spring_image_tag}"
  java_image      = "${module.registry.repository_urls["java-target"]}:${var.java_image_tag}"
  collector_image = var.collector_image

  spring_desired_count    = var.spring_desired_count
  java_desired_count      = var.java_desired_count
  collector_desired_count = var.collector_desired_count
  target_cpu              = var.target_cpu
  target_memory           = var.target_memory
  collector_cpu           = var.collector_cpu
  collector_memory        = var.collector_memory
  log_retention_days      = var.log_retention_days

  mysql_host       = module.databases.mysql_host
  mysql_port       = module.databases.mysql_port
  mysql_database   = module.databases.mysql_database
  mysql_username   = module.databases.mysql_username
  mysql_secret_arn = module.databases.mysql_secret_arn

  postgres_host       = module.databases.postgres_host
  postgres_port       = module.databases.postgres_port
  postgres_database   = module.databases.postgres_database
  postgres_username   = module.databases.postgres_username
  postgres_secret_arn = module.databases.postgres_secret_arn
}

module "load_generator" {
  source = "../../modules/load-generator"

  name_prefix                  = local.name_prefix
  private_subnet_ids           = module.network.app_subnet_ids
  lambda_security_group_id     = module.network.lambda_security_group_id
  worker_source_path           = "${path.root}/../../../lambda/worker.py"
  spring_target_url            = module.applications.spring_target_url
  java_target_url              = module.applications.java_target_url
  collector_url                = module.applications.collector_url
  collector_api_key_secret_arn = module.applications.collector_api_key_secret_arn
  reserved_concurrency         = var.lambda_reserved_concurrency
  timeout_seconds              = var.lambda_timeout_seconds
  result_retention_days        = var.result_retention_days
  log_retention_days           = var.log_retention_days
}

module "observability" {
  source = "../../modules/observability"

  name_prefix          = local.name_prefix
  ecs_cluster_name     = module.applications.cluster_name
  service_names        = module.applications.service_names
  mysql_identifier     = module.databases.mysql_identifier
  postgres_identifier  = module.databases.postgres_identifier
  lambda_function_name = module.load_generator.lambda_function_name
}

