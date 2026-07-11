resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.project}/${var.environment}/app"
  retention_in_days = var.retention_days

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "container_insights" {
  count = var.enable_container_insights ? 1 : 0

  name              = "/aws/containerinsights/${var.cluster_name}/application"
  retention_in_days = var.retention_days

  tags = var.tags
}
