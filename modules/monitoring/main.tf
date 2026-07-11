resource "random_password" "grafana_admin" {
  length  = 20
  special = false
}

# Lets Grafana's CloudWatch datasource read logs (Logs Insights included) and
# metrics directly via the pod's IRSA identity — no static AWS keys.
module "grafana_cloudwatch_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"

  role_name = "${var.cluster_name}-grafana-cloudwatch-irsa"
  role_policy_arns = {
    logs       = "arn:aws:iam::aws:policy/CloudWatchLogsReadOnlyAccess"
    cloudwatch = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
  }

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["monitoring:kube-prometheus-stack-grafana"]
    }
  }
}

# The aws-ebs-csi-driver addon (installed in modules/eks) provisions volumes,
# but the cluster ships with no default StorageClass — PVCs without an
# explicit storageClassName (like this chart's) would otherwise stay Pending
# forever. This becomes the cluster-wide default gp3 class.
resource "kubernetes_storage_class_v1" "gp3_default" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"

  parameters = {
    type = "gp3"
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.chart_version
  namespace        = "monitoring"
  create_namespace = true
  timeout          = 900

  depends_on = [kubernetes_storage_class_v1.gp3_default]

  values = [
    yamlencode({
      grafana = {
        adminPassword = random_password.grafana_admin.result

        serviceAccount = {
          annotations = {
            "eks.amazonaws.com/role-arn" = module.grafana_cloudwatch_irsa.iam_role_arn
          }
        }

        service = {
          type = "LoadBalancer"
          annotations = {
            "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
            "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
            "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
          }
        }

        persistence = {
          enabled = true
          size    = var.grafana_storage_size
        }

        sidecar = {
          dashboards = {
            enabled         = true
            searchNamespace = "ALL"
            label           = "grafana_dashboard"
          }
        }

        additionalDataSources = [
          {
            name   = "CloudWatch"
            type   = "cloudwatch"
            uid    = "cloudwatch"
            access = "proxy"
            jsonData = {
              authType      = "default"
              defaultRegion = var.aws_region
            }
          }
        ]
      }

      prometheus = {
        prometheusSpec = {
          # Without this, Prometheus only selects ServiceMonitors carrying this
          # Helm release's own label, missing ones from other releases (like
          # the task-tracker chart's).
          serviceMonitorSelectorNilUsesHelmValues = false
          podMonitorSelectorNilUsesHelmValues     = false
          ruleSelectorNilUsesHelmValues           = false

          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                accessModes = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = var.prometheus_storage_size
                  }
                }
              }
            }
          }
        }
      }
    })
  ]
}

resource "kubernetes_config_map_v1" "task_tracker_dashboard" {
  metadata {
    name      = "task-tracker-dashboard"
    namespace = "monitoring"
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "task-tracker.json" = file("${path.module}/dashboards/task-tracker.json")
  }

  depends_on = [helm_release.kube_prometheus_stack]
}

resource "kubernetes_config_map_v1" "task_tracker_e2e_dashboard" {
  metadata {
    name      = "task-tracker-e2e-dashboard"
    namespace = "monitoring"
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "task-tracker-e2e.json" = file("${path.module}/dashboards/task-tracker-e2e.json")
  }

  depends_on = [helm_release.kube_prometheus_stack]
}
