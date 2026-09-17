output "mysql_host" { value = aws_db_instance.mysql.address }
output "mysql_port" { value = aws_db_instance.mysql.port }
output "mysql_database" { value = var.mysql_database }
output "mysql_username" { value = var.mysql_username }
output "mysql_secret_arn" { value = aws_db_instance.mysql.master_user_secret[0].secret_arn }
output "mysql_identifier" { value = aws_db_instance.mysql.identifier }

output "postgres_host" { value = aws_db_instance.postgres.address }
output "postgres_port" { value = aws_db_instance.postgres.port }
output "postgres_database" { value = var.postgres_database }
output "postgres_username" { value = var.postgres_username }
output "postgres_secret_arn" { value = aws_db_instance.postgres.master_user_secret[0].secret_arn }
output "postgres_identifier" { value = aws_db_instance.postgres.identifier }

