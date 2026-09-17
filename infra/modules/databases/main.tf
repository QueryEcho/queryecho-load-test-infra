resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-db"
  subnet_ids = var.db_subnet_ids
  tags       = { Name = "${var.name_prefix}-db" }
}

resource "aws_db_instance" "mysql" {
  identifier = "${var.name_prefix}-mysql"

  engine                      = "mysql"
  instance_class              = var.mysql_instance_class
  allocated_storage           = var.allocated_storage
  max_allocated_storage       = 100
  storage_type                = "gp3"
  storage_encrypted           = true
  db_name                     = var.mysql_database
  username                    = var.mysql_username
  manage_master_user_password = true
  port                        = 3306

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.mysql_security_group]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period = 0
  deletion_protection     = false
  skip_final_snapshot     = true
  apply_immediately       = true

  performance_insights_enabled = true

  tags = { Name = "${var.name_prefix}-mysql" }
}

resource "aws_db_instance" "postgres" {
  identifier = "${var.name_prefix}-postgres"

  engine                      = "postgres"
  instance_class              = var.postgres_instance_class
  allocated_storage           = var.allocated_storage
  max_allocated_storage       = 100
  storage_type                = "gp3"
  storage_encrypted           = true
  db_name                     = var.postgres_database
  username                    = var.postgres_username
  manage_master_user_password = true
  port                        = 5432

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.postgres_security_group]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period = 0
  deletion_protection     = false
  skip_final_snapshot     = true
  apply_immediately       = true

  performance_insights_enabled = true

  tags = { Name = "${var.name_prefix}-postgres" }
}

