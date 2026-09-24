variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

variable "aws_profile" {
  description = "Local AWS CLI profile used by the AWS provider."
  type        = string
  default     = null
}

variable "aws_account_id" {
  description = "Optional deployment account guardrail. Terraform refuses a different account."
  type        = string
  default     = null
}

variable "project_name" {
  type    = string
  default = "queryecho-loadtest"
}

variable "environment" {
  type    = string
  default = "loadtest"
}

variable "vpc_cidr" {
  type    = string
  default = "10.40.0.0/16"
}

variable "spring_image_tag" {
  description = "Tag already pushed to the Spring target ECR repository."
  type        = string
  default     = "latest"
}

variable "java_image_tag" {
  description = "Tag already pushed to the pure Java target ECR repository."
  type        = string
  default     = "latest"
}

variable "collector_image_tag" {
  description = "Tag already pushed to the QueryEcho Collector ECR repository."
  type        = string
  default     = "latest"
}

variable "spring_desired_count" {
  type    = number
  default = 0
}

variable "java_desired_count" {
  type    = number
  default = 0
}

variable "collector_desired_count" {
  type    = number
  default = 0
}

variable "target_cpu" {
  type    = number
  default = 1024
}

variable "target_memory" {
  type    = number
  default = 2048
}

variable "collector_cpu" {
  type    = number
  default = 1024
}

variable "collector_memory" {
  type    = number
  default = 2048
}

variable "mysql_instance_class" {
  type    = string
  default = "db.t4g.small"
}

variable "postgres_instance_class" {
  type    = string
  default = "db.t4g.small"
}

variable "lambda_reserved_concurrency" {
  description = "Optional dedicated Lambda concurrency. Null uses the account's unreserved pool."
  type        = number
  default     = null
}

variable "lambda_timeout_seconds" {
  type    = number
  default = 300
}

variable "result_retention_days" {
  type    = number
  default = 30
}

variable "log_retention_days" {
  type    = number
  default = 14
}
