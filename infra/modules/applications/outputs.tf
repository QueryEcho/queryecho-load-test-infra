output "cluster_name" { value = aws_ecs_cluster.this.name }

output "service_names" {
  value = {
    spring    = aws_ecs_service.spring.name
    java      = aws_ecs_service.java.name
    collector = aws_ecs_service.collector.name
  }
}

output "spring_target_url" { value = "http://${aws_lb.targets.dns_name}:8081" }
output "java_target_url" { value = "http://${aws_lb.targets.dns_name}:8082" }
output "collector_url" { value = local.collector_url }
output "collector_api_key_secret_arn" { value = aws_secretsmanager_secret.collector_api_key.arn }

