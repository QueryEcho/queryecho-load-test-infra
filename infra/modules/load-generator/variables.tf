variable "name_prefix" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "lambda_security_group_id" { type = string }
variable "worker_source_path" { type = string }
variable "spring_target_url" { type = string }
variable "java_target_url" { type = string }
variable "collector_url" { type = string }
variable "collector_api_key_secret_arn" { type = string }
variable "reserved_concurrency" { type = number }
variable "timeout_seconds" { type = number }
variable "result_retention_days" { type = number }
variable "log_retention_days" { type = number }

