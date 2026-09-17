output "vpc_id" { value = aws_vpc.this.id }
output "public_subnet_ids" { value = aws_subnet.public[*].id }
output "app_subnet_ids" { value = aws_subnet.app[*].id }
output "db_subnet_ids" { value = aws_subnet.db[*].id }
output "lambda_security_group_id" { value = aws_security_group.this["lambda"].id }
output "target_alb_security_group_id" { value = aws_security_group.this["target-alb"].id }
output "target_task_security_group_id" { value = aws_security_group.this["target-task"].id }
output "collector_alb_security_group_id" { value = aws_security_group.this["collector-alb"].id }
output "collector_task_security_group_id" { value = aws_security_group.this["collector-task"].id }
output "mysql_security_group_id" { value = aws_security_group.this["mysql"].id }
output "postgres_security_group_id" { value = aws_security_group.this["postgres"].id }

