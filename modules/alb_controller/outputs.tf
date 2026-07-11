output "irsa_role_arn" {
  description = "IAM role ARN used by the aws-load-balancer-controller ServiceAccount"
  value       = module.alb_controller_irsa.iam_role_arn
}
