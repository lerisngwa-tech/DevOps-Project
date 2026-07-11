variable "chart_version" {
  description = "Version of the kube-prometheus-stack Helm chart"
  type        = string
  default     = "62.7.0"
}

variable "grafana_storage_size" {
  description = "Size of the persistent volume for Grafana"
  type        = string
  default     = "2Gi"
}

variable "prometheus_storage_size" {
  description = "Size of the persistent volume for Prometheus"
  type        = string
  default     = "10Gi"
}
