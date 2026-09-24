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

variable "aws_profile" {
  description = "Local AWS CLI profile used to create the Terraform state bucket."
  type        = string
  default     = null
}

variable "aws_account_id" {
  description = "Optional deployment account guardrail. Terraform refuses a different account."
  type        = string
  default     = null
}
