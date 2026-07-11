resource "aws_secretsmanager_secret" "app" {
  name                    = "${var.project}/${var.environment}/app"
  recovery_window_in_days = var.recovery_window_in_days

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "app" {
  secret_id     = aws_secretsmanager_secret.app.id
  secret_string = jsonencode(var.initial_secret_value)

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# IRSA role: lets a Kubernetes ServiceAccount (annotated with this role's ARN)
# read this secret via the AWS SDK, without granting node-wide access.
data "aws_iam_policy_document" "irsa_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.k8s_namespace}:${var.k8s_service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "secret_access" {
  name               = "${var.project}-${var.environment}-app-secret-irsa"
  assume_role_policy = data.aws_iam_policy_document.irsa_trust.json

  tags = var.tags
}

data "aws_iam_policy_document" "secret_access" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_secretsmanager_secret.app.arn]
  }
}

resource "aws_iam_role_policy" "secret_access" {
  name   = "${var.project}-${var.environment}-app-secret-access"
  role   = aws_iam_role.secret_access.id
  policy = data.aws_iam_policy_document.secret_access.json
}
