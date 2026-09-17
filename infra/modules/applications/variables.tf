variable "name_prefix" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "target_alb_security_group" { type = string }
variable "target_task_security_group" { type = string }
variable "collector_alb_security_group" { type = string }
variable "collector_task_security_group" { type = string }

variable "spring_image" { type = string }
variable "java_image" { type = string }
variable "collector_image" { type = string }

variable "spring_desired_count" { type = number }
variable "java_desired_count" { type = number }
variable "collector_desired_count" { type = number }
variable "target_cpu" { type = number }
variable "target_memory" { type = number }
variable "collector_cpu" { type = number }
variable "collector_memory" { type = number }
variable "log_retention_days" { type = number }

variable "mysql_host" { type = string }
variable "mysql_port" { type = number }
variable "mysql_database" { type = string }
variable "mysql_username" { type = string }
variable "mysql_secret_arn" { type = string }

variable "postgres_host" { type = string }
variable "postgres_port" { type = number }
variable "postgres_database" { type = string }
variable "postgres_username" { type = string }
variable "postgres_secret_arn" { type = string }

