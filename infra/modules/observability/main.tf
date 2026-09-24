resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${var.name_prefix}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          region = var.aws_region
          title  = "ECS CPU Utilization"
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.service_names["spring"], { label = "Spring" }],
            ["...", var.service_names["java"], { label = "Java" }],
            ["...", var.service_names["collector"], { label = "Collector" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          region = var.aws_region
          title  = "ECS Memory Utilization"
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/ECS", "MemoryUtilization", "ClusterName", var.ecs_cluster_name, "ServiceName", var.service_names["spring"], { label = "Spring" }],
            ["...", var.service_names["java"], { label = "Java" }],
            ["...", var.service_names["collector"], { label = "Collector" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          region = var.aws_region
          title  = "RDS CPU and Connections"
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.mysql_identifier, { label = "MySQL CPU" }],
            [".", "DatabaseConnections", ".", ".", { label = "MySQL Connections", yAxis = "right" }],
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.postgres_identifier, { label = "PostgreSQL CPU" }],
            [".", "DatabaseConnections", ".", ".", { label = "PostgreSQL Connections", yAxis = "right" }]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          region = var.aws_region
          title  = "Lambda Load Workers"
          view   = "timeSeries"
          period = 60
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.lambda_function_name, { stat = "Sum" }],
            [".", "Errors", ".", ".", { stat = "Sum" }],
            [".", "ConcurrentExecutions", ".", ".", { stat = "Maximum" }],
            [".", "Duration", ".", ".", { stat = "p95", yAxis = "right" }]
          ]
        }
      }
    ]
  })
}
