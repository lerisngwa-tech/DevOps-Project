output "grafana_admin_password" {
  description = "Grafana admin password"
  value       = random_password.grafana_admin.result
  sensitive   = true
}

output "grafana_service_name" {
  description = "Name of the Grafana Kubernetes Service (for kubectl get svc -n monitoring)"
  value       = "kube-prometheus-stack-grafana"
}
