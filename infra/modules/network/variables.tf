variable "name_prefix" { type = string }
variable "vpc_cidr" { type = string }

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.40.0.0/24", "10.40.1.0/24"]
}

variable "app_subnet_cidrs" {
  type    = list(string)
  default = ["10.40.10.0/24", "10.40.11.0/24"]
}

variable "db_subnet_cidrs" {
  type    = list(string)
  default = ["10.40.20.0/24", "10.40.21.0/24"]
}

