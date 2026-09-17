variable "name_prefix" { type = string }
variable "db_subnet_ids" { type = list(string) }
variable "mysql_security_group" { type = string }
variable "postgres_security_group" { type = string }
variable "mysql_instance_class" { type = string }
variable "postgres_instance_class" { type = string }

variable "mysql_database" {
  type    = string
  default = "querytest"
}

variable "postgres_database" {
  type    = string
  default = "queryecho"
}

variable "mysql_username" {
  type    = string
  default = "queryecho_admin"
}

variable "postgres_username" {
  type    = string
  default = "queryecho_admin"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

