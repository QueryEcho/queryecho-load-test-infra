output "ecr_repository_urls" {
  value = module.registry.repository_urls
}

output "spring_target_url" {
  value = module.applications.spring_target_url
}

output "java_target_url" {
  value = module.applications.java_target_url
}

output "collector_url" {
  value = module.applications.collector_url
}

output "lambda_function_name" {
  value = module.load_generator.lambda_function_name
}

output "result_bucket_name" {
  value = module.load_generator.result_bucket_name
}

output "cloudwatch_dashboard_name" {
  value = module.observability.dashboard_name
}

