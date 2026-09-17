variable "project_name" {
  description = "Resource name prefix."
  type        = string
  default     = "queryecho-loadtest"
}

variable "aws_region" {
  description = "AWS region for the Terraform state bucket."
  type        = string
  default     = "ap-northeast-2"
}

