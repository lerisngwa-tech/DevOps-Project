# EKS Terraform Platform

Multi-AZ EKS platform on AWS (`us-east-1`) with Terraform, split into reusable modules and three isolated environments (`dev`, `stg`, `prod`).

## What this deploys

- **VPC** (`modules/vpc`): 1 VPC across 3 AZs, public + private subnets, NAT gateway(s)
- **EKS** (`modules/eks`): cluster with EKS Managed Node Groups (Auto Scaling Group under the hood), `coredns`/`kube-proxy`/`vpc-cni`/`aws-ebs-csi-driver` addons, IRSA enabled, both aws-auth ConfigMap and API access-entry authentication (`API_AND_CONFIG_MAP`), control-plane logs to CloudWatch
- **ECR** (`modules/ecr`): application image repository with scan-on-push and an untagged-image lifecycle policy
- **S3 app bucket** (`modules/s3_app_bucket`): private, versioned, encrypted bucket + an IRSA IAM role scoping bucket access to a specific Kubernetes ServiceAccount
- **Secrets Manager** (`modules/secrets_manager`): an application secret + an IRSA IAM role scoping read access to a specific Kubernetes ServiceAccount
- **CloudWatch** (`modules/cloudwatch`): application + Container Insights log groups with configurable retention
- **AWS Load Balancer Controller** (`modules/alb_controller`): installed via Helm with IRSA, so Kubernetes `Ingress`/`Service` objects can provision ALBs/NLBs
- **RDS** (`modules/rds`): a private, encrypted Postgres instance (security group only allows traffic from the EKS node/pod security group), Multi-AZ per env, with live connection details in a dedicated Secrets Manager secret + IRSA role

## Prerequisites

- Terraform >= 1.6
- AWS CLI configured with credentials that can create the resources above
- `kubectl` and `helm` (for post-apply verification)

## First-time setup: bootstrap the remote backend

The S3 bucket + DynamoDB table used as the Terraform backend must exist before any environment can use them, so they're created once with local state:

```
cd bootstrap
terraform init
terraform apply -var="state_bucket_name=<your-globally-unique-bucket-name>"
```

Note the `state_bucket_name` and `lock_table_name` outputs, then update the `bucket` / `dynamodb_table` values in each `envs/<env>/backend.tf` to match.

## Deploying an environment

```
cd envs/dev        # or stg, prod
terraform init
terraform plan
terraform apply
```

Before applying, edit `envs/<env>/terraform.tfvars`:
- Set `app_bucket_suffix` to something globally unique (e.g. your AWS account ID)
- Adjust CIDRs, node sizing, and `single_nat_gateway` as needed (prod defaults to one NAT gateway per AZ; dev/stg default to a single shared NAT gateway)

Repeat per environment. Each environment has its own state file (`envs/<env>/terraform.tfstate` inside the shared backend bucket) and is fully isolated from the others.

## Post-apply verification

```
aws eks update-kubeconfig --name <cluster_name> --region us-east-1   # see the `configure_kubectl` output
kubectl get nodes
kubectl get configmap aws-auth -n kube-system
aws eks list-access-entries --cluster-name <cluster_name>
kubectl get pods -n kube-system | grep aws-load-balancer-controller
```

## Giving the application access to its S3 bucket / secret

The `s3_app_bucket` and `secrets_manager` modules create IRSA-ready IAM roles (see the `app_bucket_irsa_role_arn` and `app_secret_irsa_role_arn` outputs), but the corresponding Kubernetes ServiceAccounts must be created and annotated by whatever deploys the application (e.g. a Helm chart or manifests, outside this Terraform project):

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-s3-access
  namespace: default
  annotations:
    eks.amazonaws.com/role-arn: <app_bucket_irsa_role_arn output>
```

Pods using this ServiceAccount can then call the AWS SDK directly (`s3.GetObject`, `secretsmanager.GetSecretValue`, etc.) without static credentials.

## Sample application: Task & Project Tracker

`app/` contains a Node.js + Express REST API (projects, tasks, task attachments) that demonstrates the full platform: it stores structured data in the RDS Postgres instance and uploads task attachments to the S3 app bucket, all authenticated via IRSA (no static AWS credentials anywhere).

- **Data model**: `users`, `projects`, `tasks`, `attachments` — schema in `app/src/db/schema.sql`, applied idempotently at pod startup (no migration framework).
- **Credentials**: the app never receives a DB password via Kubernetes Secret/ConfigMap. At startup it fetches live DB credentials from the RDS module's Secrets Manager secret using an explicit `AssumeRoleWithWebIdentity` call (`app/src/aws/secrets.js`, via `db_secret_irsa_role_arn`). S3 access uses the default AWS SDK credential chain, backed by the existing `s3_app_bucket` IRSA role.
- **Endpoints**: `GET /healthz` (liveness), `GET /readyz` (DB connectivity, readiness), `/api/projects`, `/api/projects/:id/tasks`, `/api/tasks/:id`, `/api/tasks/:id/attachments`.
- **No authentication** on the API — this is a demo app, not intended to hold real data.

### Build and deploy

From `app/`, everything reads straight from the matching `envs/<env>` Terraform outputs — nothing is hardcoded:

```
cd app
make deploy ENV=dev     # docker build -> ECR push -> helm upgrade --install
```

This requires `docker`, `helm`, and `terraform apply` already run for that environment (so `terraform output` has real values). See `app/Makefile` for the individual `build`/`push`/`deploy` targets.

### Verify end-to-end

```
kubectl get pods -l app.kubernetes.io/name=task-tracker
kubectl get ingress task-tracker -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
curl http://<alb-hostname>/healthz
curl http://<alb-hostname>/readyz          # 200 confirms RDS connectivity end-to-end
curl -X POST http://<alb-hostname>/api/projects -H 'content-type: application/json' -d '{"name":"Demo"}'
```

## CI/CD (GitHub Actions)

Two workflows automate the app build/deploy (Terraform stays a manual CLI workflow, unchanged):

- **`.github/workflows/app-ci.yml`** — runs on every PR touching `app/**`: installs dependencies, builds the Docker image (validation only, not pushed), and `helm lint`s the chart.
- **`.github/workflows/app-cd.yml`** — runs on every push to `main` touching `app/**` (deploys to `dev` automatically), and can be triggered manually from the Actions tab (`workflow_dispatch`) with an `environment` input (`dev`/`stg`/`prod`) to promote a build to `stg` or `prod`. It builds the image, tags it with the commit SHA, pushes to ECR, and runs `helm upgrade --install` — the same shape as `app/Makefile`'s `deploy` target, but reading pre-populated GitHub Environment variables instead of live `terraform output` calls.

### One-time setup (required before the CD workflow will work)

1. **Create three GitHub Environments** (repo Settings → Environments): `dev`, `stg`, `prod`. Optionally add required reviewers on `stg`/`prod` for a manual approval gate.

2. **Add these Variables to each Environment**, using that environment's `terraform output` (from `envs/<env>/`):

   | Variable | Source |
   |---|---|
   | `AWS_REGION` | `us-east-1` |
   | `EKS_CLUSTER_NAME` | `terraform output -raw cluster_name` |
   | `ECR_REPOSITORY_URL` | `terraform output -raw ecr_repository_url` |
   | `S3_BUCKET_NAME` | `terraform output -raw app_bucket_name` |
   | `APP_BUCKET_IRSA_ROLE_ARN` | `terraform output -raw app_bucket_irsa_role_arn` |
   | `DB_SECRET_ARN` | `terraform output -raw db_secret_arn` |
   | `DB_SECRET_IRSA_ROLE_ARN` | `terraform output -raw db_secret_irsa_role_arn` |
   | `K8S_NAMESPACE` | `terraform output -raw k8s_namespace` (e.g. `myapp-dev`) |

3. **Create a CI IAM user** (or reuse one) and attach the least-privilege policy in [`.github/ci-iam-policy.json`](.github/ci-iam-policy.json) (ECR push on the `myapp-*-app` repos + `eks:DescribeCluster` on the `myapp-*` clusters). Add its access key as **repo-level secrets**: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`.

4. **Grant that CI user Kubernetes access on each cluster** (the clusters use `authentication_mode = API_AND_CONFIG_MAP`, so an IAM identity also needs an explicit access entry to get past Kubernetes RBAC), once per environment — replace `<namespace>` with that environment's `k8s_namespace` output (e.g. `myapp-dev`):

   ```
   aws eks create-access-entry \
     --cluster-name <cluster_name> \
     --principal-arn <ci-iam-user-arn> \
     --region us-east-1

   aws eks associate-access-policy \
     --cluster-name <cluster_name> \
     --principal-arn <ci-iam-user-arn> \
     --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy \
     --access-scope type=namespace,namespaces=<namespace> \
     --region us-east-1
   ```

Once these are in place, merging to `main` auto-deploys to `dev`; use **Actions → App CD → Run workflow** and pick `stg` or `prod` to promote the same pipeline to those environments.
