variable "aws_region" { type = string }
variable "name_prefix" { type = string }
variable "ecs_cluster_name" { type = string }
variable "service_names" { type = map(string) }
variable "mysql_identifier" { type = string }
variable "postgres_identifier" { type = string }
variable "lambda_function_name" { type = string }
