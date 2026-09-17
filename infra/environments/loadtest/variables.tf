variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
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

variable "collector_image" {
  description = "Full QueryEcho image URI. Defaults to the public GHCR image when null."
  type        = string
  default     = "ghcr.io/queryecho/queryecho-app:0.2.0"
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
  type    = number
  default = 10
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

