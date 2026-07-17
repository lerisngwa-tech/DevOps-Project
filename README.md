# Task Tracker — EKS Platform

A Task & Project Tracker application (Node.js/Express, server-rendered UI + JSON API) running on a self-provisioned, multi-AZ Amazon EKS platform: VPC, EKS, RDS Postgres, S3, ECR, Secrets Manager, an ALB-fronted Ingress, GitHub Actions CI/CD, and a Prometheus/Grafana/CloudWatch observability stack. Everything below reflects what is actually deployed and running in the `dev` environment (account `246312965731`, `us-east-1`), not an aspirational design.

## Table of contents

- [Platform Overview](#platform-overview)
- [Architecture](#architecture)
- [Application Deep Dive](#application-deep-dive)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Setup & Deployment](#setup--deployment)
- [CI/CD Pipeline](#cicd-pipeline)
- [Security](#security)
- [Availability & Resilience](#availability--resilience)
- [Deployment Strategy](#deployment-strategy)
- [Troubleshooting](#troubleshooting)
- [Project Highlights](#project-highlights)
- [Resources](#resources)
- [Contributing](#contributing)
- [Author](#author)

---

## Platform Overview

| Layer | What it is | Where |
|---|---|---|
| Compute | EKS 1.31, 1 managed node group, `t3.medium`, 1–3 nodes (dev) | `modules/eks`, `envs/dev/terraform.tfvars` |
| Network | 1 VPC, 3 AZs (`us-east-1a/b/c`), public + private subnets | `modules/vpc` |
| Database | RDS Postgres 16.4, `db.t4g.micro` (dev), private-only | `modules/rds` |
| Object storage | S3 bucket for task attachments, versioned + encrypted | `modules/s3_app_bucket` |
| Container registry | 1 ECR repo, scan-on-push | `modules/ecr` |
| Secrets | 2 Secrets Manager secrets (app + RDS), IRSA-gated read access | `modules/secrets_manager`, `modules/rds` |
| Ingress | AWS Load Balancer Controller → ALB → Ingress | `modules/alb_controller`, `helm/task-tracker/templates/ingress.yaml` |
| Observability | CloudWatch (control-plane logs + Container Insights) + kube-prometheus-stack (Prometheus/Grafana/Alertmanager) | `modules/cloudwatch`, `modules/eks` (`amazon-cloudwatch-observability` add-on), `modules/monitoring` |
| CI/CD | GitHub Actions: PR validation + build/push/deploy | `.github/workflows/app-ci.yml`, `.github/workflows/app-cd.yml` |
| App | Node.js 20 + Express, EJS server-rendered UI, JSON API, Postgres, S3, Prometheus metrics | `app/` |

Three environments are defined (`envs/dev`, `envs/stg`, `envs/prod`) sharing the same modules with different `.tfvars`. **Only `dev` is currently deployed** — `stg`/`prod` exist as validated-but-unapplied Terraform configuration.

---

## Architecture

### Network

- 1 VPC per environment (`10.0.0.0/16` dev, `10.1.0.0/16` stg, `10.2.0.0/16` prod), 3 AZs, one public + one private subnet per AZ (`modules/vpc/main.tf`, wraps `terraform-aws-modules/vpc/aws ~> 5.13`).
- NAT strategy: dev/stg use `single_nat_gateway = true` (one shared NAT); prod uses `single_nat_gateway = false` (one NAT per AZ), set in each env's `terraform.tfvars`.
- Public subnets are tagged `kubernetes.io/role/elb = 1`; private subnets `kubernetes.io/role/internal-elb = 1` — required for the AWS Load Balancer Controller's subnet auto-discovery.

### Compute

- EKS cluster, `authentication_mode = "API_AND_CONFIG_MAP"` (both the `aws-auth` ConfigMap and EKS API access entries work simultaneously), `enable_irsa = true` (`modules/eks/main.tf`).
- One EKS managed node group named `default`: `t3.medium`, `ON_DEMAND`, min 1 / max 3 / desired 2 (dev — see `envs/dev/terraform.tfvars`).
- Managed add-ons installed via `cluster_addons`: `coredns`, `kube-proxy`, `vpc-cni`, `aws-ebs-csi-driver`, `metrics-server`, `amazon-cloudwatch-observability`.
- Namespaces in use: `myapp-dev` (the application — see [Known issue](#security) below on how this got its name), `kube-system` (cluster add-ons + ALB controller), `monitoring` (Prometheus stack), `amazon-cloudwatch` (Fluent Bit + CloudWatch Agent, from the observability add-on).

### Data layer

- **RDS**: Postgres `16.4` (`modules/rds/variables.tf` default `engine_version`), `gp3` storage, `storage_encrypted = true`, `publicly_accessible = false`, `db.t4g.micro` in dev / `db.t4g.small` in stg / `db.t4g.medium` in prod, `multi_az = true` in prod only. Security group allows inbound `5432` **only** from `module.eks.node_security_group_id` (`modules/rds/main.tf`) — no `0.0.0.0/0` rule anywhere in this repo.
- **S3**: one bucket per environment (`myapp-dev-app-246312965731`), versioning + SSE-S3 enabled, `block_public_acls`/`block_public_policy`/`ignore_public_acls`/`restrict_public_buckets` all `true` (`modules/s3_app_bucket/main.tf`). Objects keyed `tasks/<task-id>/<attachment-uuid>-<filename>` (`app/src/routes/attachments.js`).
- **ECR**: `myapp-dev-app`, `image_tag_mutability = "IMMUTABLE"`, `scan_on_push = true`, lifecycle policy expiring untagged images after 14 days (dev) / 30 days (prod) (`modules/ecr/main.tf`).

### Observability

- **CloudWatch**: EKS control-plane logging enabled for all 5 log types (`api`, `audit`, `authenticator`, `controllerManager`, `scheduler`) via `cluster_enabled_log_types` in `modules/eks/main.tf` — this creates `/aws/eks/myapp-dev/cluster` automatically, no agent required. Application/container logs are shipped separately by the `amazon-cloudwatch-observability` EKS add-on (Fluent Bit + CloudWatch Agent, IRSA role `myapp-dev-cloudwatch-observability-irsa`) into `/aws/containerinsights/myapp-dev/application`.
- **Prometheus/Grafana**: `kube-prometheus-stack` Helm chart (`modules/monitoring/main.tf`), Grafana exposed on a dedicated internet-facing NLB (`service.beta.kubernetes.io/aws-load-balancer-type: external`, `aws-load-balancer-nlb-target-type: ip`) — deliberately separate from the app's ALB. `prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues = false` so Prometheus scrapes `ServiceMonitor` objects cluster-wide, not just ones carrying its own Helm release label.
- Grafana has two datasources: `Prometheus` (chart default) and a custom `CloudWatch` datasource (`uid: cloudwatch`, `authType: default`) authenticating via the `myapp-dev-grafana-cloudwatch-irsa` IRSA role — `CloudWatchLogsReadOnlyAccess` + `CloudWatchReadOnlyAccess` + a scoped inline `ec2:DescribeRegions` statement.
- Two dashboards ship as code (`modules/monitoring/dashboards/*.json`, loaded via a labeled `ConfigMap` + Grafana's sidecar): `task-tracker.json` (app-only: request rate, p95 latency, error rate, pod CPU/memory) and `task-tracker-e2e.json` (the same, plus RDS CPU/connections/free-storage from CloudWatch metrics and a live CloudWatch Logs panel).

---

## Application Deep Dive

The app is **one Node.js/Express service** (`app/`), not separate frontend/backend/worker processes — it serves both a JSON API and a server-rendered UI from the same process.

### Routes & UI (`app/src/routes/`, `app/src/views/`)

- JSON API, mounted under `/api`: `projects.js` (`GET/POST /api/projects`, `GET/PUT/DELETE /api/projects/:id`), `tasks.js` (nested + flat task routes), `attachments.js` (`multer` memory storage → S3 upload, presigned-URL download, delete).
- Server-rendered UI, mounted at root (`ui.js`): `/projects`, `/projects/new`, `/projects/:id`, `/tasks/:id` — EJS templates in `app/src/views/`, plain HTML forms (`express.urlencoded`), no client-side JS framework, styled via one static `app/src/public/style.css`.
- `health.js`: `GET /healthz` (liveness, always 200) and `GET /readyz` (readiness — runs `SELECT 1` against the pool, returns `503` on failure rather than throwing, so a transient DB outage marks the pod not-ready instead of crash-looping).

### Database layer (`app/src/db/`)

- `pool.js` builds a `pg.Pool` from credentials fetched once at startup (not per-request) via `aws/secrets.js`.
- `migrate.js` runs `schema.sql` (idempotent `CREATE TABLE IF NOT EXISTS`) on every boot — no migration framework, no versioning table.
- `schema.sql` defines `users`, `projects`, `tasks`, `attachments`; IDs are `UUID` with no DB-side default — generated in app code via `crypto.randomUUID()` to avoid depending on the `pgcrypto` extension.

### AWS integration (`app/src/aws/`)

- `s3.js` uses the AWS SDK's **default credential chain** — the pod's IRSA-annotated ServiceAccount (`app-s3-access`) supplies credentials automatically, no keys in code or config.
- `secrets.js` explicitly assumes a **second** IRSA role (`db_secret_irsa_role_arn`, via `fromTokenFile`) to read the RDS credentials secret — a pod gets exactly one ServiceAccount/role via annotation, so reaching a second role requires one explicit `AssumeRoleWithWebIdentity` call rather than the default chain.
- No database host, username, or password is ever stored in a Kubernetes `ConfigMap` or `Secret` — only the Secrets Manager ARN and the role ARN to assume are.

### Metrics (`app/src/metrics.js`)

- `prom-client` `Registry` with `collectDefaultMetrics()` (Node.js process stats) plus two custom instruments: `http_requests_total` (Counter) and `http_request_duration_seconds` (Histogram), both labeled `method`/`route`/`status_code`.
- `GET /metrics` exposes them in Prometheus text format; a `metricsMiddleware` in `server.js` records every request before it reaches a route handler.
- Scraped via `helm/task-tracker/templates/servicemonitor.yaml`, a `ServiceMonitor` (`monitoring.coreos.com/v1`) selecting the `task-tracker` Service's `http` port at path `/metrics` every 30s, `jobLabel: app.kubernetes.io/name` (so the Prometheus `job` label reads `task-tracker`, matching the dashboard queries).

---

## Project Structure

```text
.
├── bootstrap/                  # One-time, local-state config: creates the S3 state bucket + DynamoDB lock table
├── modules/
│   ├── vpc/                    # Wraps terraform-aws-modules/vpc/aws
│   ├── eks/                    # Wraps terraform-aws-modules/eks/aws + EBS CSI / CloudWatch Observability IRSA
│   ├── ecr/                    # ECR repo + lifecycle policy
│   ├── s3_app_bucket/          # App S3 bucket + IRSA role
│   ├── secrets_manager/        # Generic app secret + IRSA role
│   ├── rds/                    # Postgres + dedicated Secrets Manager secret + IRSA role
│   ├── cloudwatch/             # Application + Container Insights log groups
│   ├── alb_controller/         # AWS Load Balancer Controller (helm_release) + IRSA role
│   └── monitoring/             # kube-prometheus-stack + Grafana CloudWatch datasource + dashboards-as-code
│       └── dashboards/*.json
├── envs/
│   ├── dev/                    # backend.tf, providers.tf, main.tf, variables.tf, terraform.tfvars, outputs.tf
│   ├── stg/                    # (defined, not yet applied)
│   └── prod/                   # (defined, not yet applied)
├── app/
│   ├── src/
│   │   ├── routes/             # projects.js, tasks.js, attachments.js, health.js, ui.js
│   │   ├── views/              # EJS templates (projects/, tasks/, partials/)
│   │   ├── db/                 # pool.js, migrate.js, schema.sql
│   │   ├── aws/                # s3.js, secrets.js
│   │   ├── public/style.css
│   │   ├── metrics.js
│   │   ├── config.js
│   │   └── server.js
│   ├── Dockerfile              # Multi-stage, non-root, node:20-alpine
│   └── Makefile                # Local build/push/deploy (uses live terraform output values)
├── helm/task-tracker/
│   ├── Chart.yaml               # name: task-tracker, version 0.1.0
│   ├── values.yaml / values-{dev,stg,prod}.yaml
│   └── templates/               # deployment, service, ingress, serviceaccount, configmap, servicemonitor
├── .github/
│   ├── ci-iam-policy.json       # Least-privilege policy for the CI IAM user
│   └── workflows/
│       ├── app-ci.yml           # PR validation
│       └── app-cd.yml           # Build → push → deploy
└── README.md
```

---

## Prerequisites

| Tool | Notes |
|---|---|
| Terraform | Used at `~1.15.6` this session; state stored in S3 (`bootstrap/`) |
| AWS CLI | Configured for account `246312965731`, region `us-east-1` |
| `kubectl` | Any recent version |
| `helm` | `v3.15.3` pinned in CI (`app-ci.yml`, `app-cd.yml`) |
| `gh` (GitHub CLI) | Used for repo/environment/secret setup — see [CI/CD Pipeline](#cicd-pipeline) |
| Docker | Required to build `app/Dockerfile` locally — **not installed in this project's dev shell**; all image builds so far have run through GitHub Actions, not locally |

> **Known issue:** Docker and Node/npm are not installed in the environment this project was built in. `app/package.json` has no committed `package-lock.json`; the Dockerfile and CI both use `npm install` (not `npm ci`) to avoid requiring one. Generating and committing a lockfile is a documented but unfinished follow-up.

---

## Setup & Deployment

### 1. Bootstrap the remote backend (one time)

```bash
cd bootstrap
terraform init
terraform apply -var="state_bucket_name=<globally-unique-bucket-name>"
```

Creates an S3 bucket (versioned, `AES256` SSE, all public access blocked) and a DynamoDB table (`terraform-state-locks`), using **local** state by design. Live values in this deployment: bucket `myapp-tfstate-246312965731`.

### 2. Fix the placeholders

Each `envs/<env>/backend.tf` needs `bucket` to match the bootstrap output; each `envs/<env>/terraform.tfvars` needs `app_bucket_suffix` set to a real, globally-unique value (this deployment uses the AWS account ID, `246312965731`).

### 3. Staged apply — VPC + EKS first, then everything else

```bash
cd envs/dev
terraform init
terraform apply -target=module.vpc -target=module.eks   # ~15–20 min: EKS control plane + node group
terraform apply                                          # everything else: ECR, S3, RDS, ALB controller, monitoring
```

The two-stage apply exists because the `kubernetes`/`helm` providers (`envs/dev/providers.tf`) authenticate via `aws_eks_cluster_auth`, which needs a cluster that doesn't exist yet on a from-scratch run.

### 4. One-time manual steps (not Terraform-managed)

```bash
aws eks update-kubeconfig --name myapp-dev --region us-east-1
kubectl create namespace myapp-dev          # see Security section — CI's IAM policy can't create namespaces
kubectl apply -f - <<'EOF'                  # ServiceMonitor RBAC — see Troubleshooting
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: prometheus-operator-crds-editor
  namespace: myapp-dev
rules:
  - apiGroups: ["monitoring.coreos.com"]
    resources: ["servicemonitors", "podmonitors", "prometheusrules"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: myapp-github-actions-ci-prometheus-operator-crds
  namespace: myapp-dev
subjects:
  - kind: User
    name: arn:aws:iam::246312965731:user/myapp-github-actions-ci
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: prometheus-operator-crds-editor
  apiGroup: rbac.authorization.k8s.io
EOF
```

### 5. Deploy the app

```bash
cd app
make deploy ENV=dev   # docker build -> ECR push -> helm upgrade --install, all values from `terraform output`
```

Or let CI do it — see [CI/CD Pipeline](#cicd-pipeline).

### 6. Verify

```bash
kubectl get pods -n myapp-dev
kubectl get ingress -n myapp-dev -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'
curl http://<that-hostname>/healthz     # -> {"status":"ok"}
curl http://<that-hostname>/readyz      # -> {"status":"ready"} (confirms RDS connectivity)
```

---

## CI/CD Pipeline

Two workflows, both AWS-only (no Azure-branded actions — see [Troubleshooting](#troubleshooting)):

**`app-ci.yml`** — `pull_request` touching `app/**`: `npm install`, `npm test --if-present` (currently a no-op, no test suite exists), `docker build` (validation only, not pushed), `helm lint` against the chart with placeholder `--set` values.

**`app-cd.yml`** ("Build and Deploy") — `push` to `main` touching `app/**` (auto-deploys to `dev`) or `workflow_dispatch` with an `environment` choice (`dev`/`stg`/`prod`, default `dev`):

| Job | Steps |
|---|---|
| `test` | checkout, Node 20, `npm install`, `npm test --if-present` |
| `build-and-push` | compute tag `<env>-<timestamp>-<short-sha>`, configure AWS creds, ECR login, `docker build`/`docker push` |
| `deploy` | configure AWS creds, install `kubectl`/`helm` via direct `curl` (not `azure/setup-*`), `aws eks update-kubeconfig`, `helm upgrade --install` with `--set` values sourced from `vars.*` (no `--create-namespace` — see Security), `kubectl get pods`/`get ingress` as a final check |

Required one-time GitHub setup (all done via `gh` CLI this session): 3 GitHub Environments (`dev`/`stg`/`prod`), 7 environment variables per env populated from `terraform output` (`AWS_REGION`, `EKS_CLUSTER_NAME`, `ECR_REPOSITORY_URL`, `S3_BUCKET_NAME`, `APP_BUCKET_IRSA_ROLE_ARN`, `DB_SECRET_ARN`, `DB_SECRET_IRSA_ROLE_ARN`, `K8S_NAMESPACE`), repo secrets `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` for a dedicated `myapp-github-actions-ci` IAM user (policy: `.github/ci-iam-policy.json`).

> **Tradeoff, by design:** the CI IAM user's credentials are static access keys stored as GitHub secrets, not OIDC federation. Chosen explicitly over OIDC when the pipeline was first built — simpler to wire up, at the cost of a long-lived credential sitting in GitHub rather than short-lived per-run tokens.

---

## Security

- **Dual EKS authentication**: `authentication_mode = "API_AND_CONFIG_MAP"` — both the legacy `aws-auth` ConfigMap and modern EKS API access entries work. Verified via `kubectl get configmap aws-auth -n kube-system` and `aws eks list-access-entries --cluster-name myapp-dev`.
- **IRSA roles** — every AWS permission a pod needs is scoped to a specific `namespace:service-account`, never the node's own instance role:

  | Role | Namespace:ServiceAccount | Grants |
  |---|---|---|
  | `myapp-dev-app-bucket-irsa` | `myapp-dev:app-s3-access` | `s3:GetObject/PutObject/DeleteObject` on the app bucket's objects, `s3:ListBucket` on the bucket |
  | `myapp-dev-app-secret-irsa` | `myapp-dev:app-secrets-access` | `secretsmanager:GetSecretValue/DescribeSecret` on the generic app secret |
  | `myapp-dev-db-secret-irsa` | `myapp-dev:app-s3-access` | `secretsmanager:GetSecretValue/DescribeSecret` on the RDS credentials secret |
  | `myapp-dev-ebs-csi-irsa` | `kube-system:ebs-csi-controller-sa` | `AmazonEBSCSIDriverPolicy` |
  | `myapp-dev-alb-controller-irsa` | `kube-system:aws-load-balancer-controller` | AWS Load Balancer Controller policy |
  | `myapp-dev-cloudwatch-observability-irsa` | `amazon-cloudwatch:cloudwatch-agent`, `amazon-cloudwatch:fluent-bit` | `CloudWatchAgentServerPolicy` |
  | `myapp-dev-grafana-cloudwatch-irsa` | `monitoring:kube-prometheus-stack-grafana` | `CloudWatchLogsReadOnlyAccess`, `CloudWatchReadOnlyAccess`, inline `ec2:DescribeRegions` |

- **Network isolation** — the RDS security group's only ingress rule is port `5432` from `module.eks.node_security_group_id` (`modules/rds/main.tf`); no `0.0.0.0/0` rule exists anywhere in this repo.
- **CI IAM user is deliberately narrow** — `myapp-github-actions-ci`'s AWS policy (`.github/ci-iam-policy.json`) only grants ECR push on `myapp-*-app` repos and `eks:DescribeCluster` on `myapp-*` clusters; its Kubernetes access via `AmazonEKSEditPolicy` is scoped to the `myapp-dev` namespace only, plus the one narrow Role/RoleBinding for `ServiceMonitor`/`PodMonitor`/`PrometheusRule` (see Troubleshooting).

> **Known issue:** the API has no authentication at all — any request reaching the ALB can read/write/delete data. This was a confirmed, deliberate scope decision for this demo, documented since the app was first built, not an oversight.

> **Known issue:** CORS is wide open (`app.use(cors())` with no origin restriction in `app/src/server.js`) — combined with no auth, any website's JavaScript can call this API on a visitor's behalf.

> **Known issue:** `app/src/db/pool.js` sets `ssl: { rejectUnauthorized: false }` — the Postgres connection is encrypted but the server certificate is never validated, so it isn't protected against MITM even though traffic stays inside the VPC.

> **Known issue:** `app/src/db/pool.js`'s `pg.Pool` has no `.on('error', ...)` listener. `node-postgres` requires one — an idle client hitting a network error without a listener can crash the whole Node process, not just fail one request.

> **Tradeoff, by design:** Grafana is reachable on an internet-facing NLB protected only by its admin password (`terraform output -raw grafana_admin_password`) — no IP allowlist, SSO, or WAF. The app's own ALB likewise has no WAF association and no ACM certificate (`http://` only). Both public entry points rely on credentials/app logic rather than network-level restriction.

> **Known issue:** the RBAC `Role`/`RoleBinding` granting the CI user `ServiceMonitor`/`PodMonitor`/`PrometheusRule` access (Step 4 above) is applied by hand via `kubectl`, not Terraform-managed — it will need to be reapplied manually for `stg`/`prod` when those environments are eventually deployed.

---

## Availability & Resilience

- **Multi-AZ by default** — all three environments span 3 AZs for subnets and the EKS node group (`modules/vpc`, `modules/eks`). RDS Multi-AZ (`db_multi_az`) is `true` in prod only; dev/stg run single-AZ RDS to save cost. NAT gateways follow the same split: `single_nat_gateway = true` for dev/stg, `false` (one per AZ) for prod.
- **Node group sizing per environment** (`envs/<env>/terraform.tfvars`):

  | | dev | stg | prod |
  |---|---|---|---|
  | Instance type | `t3.medium` | `t3.medium` | `t3.large` |
  | Min / Max / Desired | 1 / 3 / 2 | 2 / 4 / 2 | 3 / 6 / 3 |
  | RDS class | `db.t4g.micro` | `db.t4g.small` | `db.t4g.medium` |
  | RDS Multi-AZ | No | No | Yes |
  | Log retention | 14 days | 30 days | 90 days |

- **Verified module behavior**: `terraform-aws-modules/eks/aws`'s `eks-managed-node-group` submodule sets `lifecycle { ignore_changes = [scaling_config[0].desired_size, ...] }` (confirmed at `modules/eks-managed-node-group/main.tf:478-479` in the vendored module source) — so once a node group exists, changing `desired_size` in `.tfvars` and re-applying has no effect; only `min_size`/`max_size` changes take effect on a later apply. Rescaling `desired_size` on a live node group requires `aws eks update-nodegroup-config --scaling-config`.
- **App readiness/liveness**: `GET /healthz` (liveness, unconditional 200) and `GET /readyz` (readiness, `SELECT 1` against Postgres, `503` on failure) — wired into `helm/task-tracker/templates/deployment.yaml`'s probes, so a DB outage marks the pod not-ready (out of the ALB's target group) instead of crash-looping.
- **Cluster addon versions are managed automatically** — every entry in `modules/eks/main.tf`'s `cluster_addons` block uses `most_recent = true` rather than a pinned version, so `terraform apply` picks up new addon releases (verified: `kube-proxy`/`metrics-server` versions changed on a routine apply during this session with no config change).

---

## Deployment Strategy

- **Promotion model**: a push to `main` touching `app/**` always deploys to `dev` automatically (`inputs.environment || 'dev'` in `app-cd.yml`). Promoting to `stg`/`prod` requires a manual `workflow_dispatch` run with an explicit environment selection — there is no automatic promotion path, and `stg`/`prod` haven't been deployed yet regardless.
- **Image tagging**: every build is tagged `<environment>-<timestamp>-<short-sha>` (e.g. `dev-20260711-202523-f15d628`), computed once in the `build-and-push` job and passed to `deploy` via `needs.build-and-push.outputs.image_tag` — no `latest` tag is used, every deploy is traceable to an exact commit.
- **Helm strategy**: `helm upgrade --install`, values injected via `--set` at deploy time (image repository/tag, IRSA role ARNs, S3 bucket name, DB secret ARN) rather than baked into the committed `values-<env>.yaml` files, which ship with those fields empty.
- **Terraform apply ordering**: documented above in Setup — VPC + EKS staged first, then everything else, because the `kubernetes`/`helm` providers can't authenticate until the cluster exists.
- **Rollout verification**: the CI `deploy` job's final step runs `kubectl get pods -l app.kubernetes.io/name=task-tracker` and `kubectl get ingress` and prints the result — there is no `--wait`-based hard failure gate beyond Helm's own `--wait --timeout 5m` on the `helm upgrade` call itself.

---

## Troubleshooting

Every entry below is a real problem hit and fixed during this project's build-out, with the literal error text observed.

### `terraform plan` wants to downgrade the EKS cluster version

```
~ version = "1.31" -> "1.30"
```

**Cause**: `envs/dev/terraform.tfvars` still said `cluster_version = "1.30"` after AWS had already auto-upgraded the live control plane to `1.31`. EKS does not support downgrading a cluster version — applying this as-is would have errored mid-apply.
**Fix**: updated `cluster_version` in `terraform.tfvars` to `"1.31"` to match the live cluster, then re-planned to confirm the diff disappeared before touching anything else.

### `Error: UPGRADE FAILED: another operation (install/upgrade/rollback) is in progress`

**Cause**: a manual local `helm upgrade` and a CI-triggered deploy (fired by an auto-committed file change from an editor extension) raced to update the same Helm release simultaneously.
**Fix**: none needed — the CI-triggered run won the race and completed successfully (`helm history` showed revision 2, `deployed`); the manual command's failure was expected fallout, not a real problem.

### ALB returns 404 on its own hostname

```bash
$ curl http://k8s-default-tasktrac-....elb.amazonaws.com/healthz
# HTTP 404
$ curl -H "Host: task-tracker-dev.example.com" http://k8s-default-tasktrac-....elb.amazonaws.com/healthz
# HTTP 200
```

**Cause**: the Ingress had `host: task-tracker-dev.example.com` (a placeholder domain from `values-dev.yaml` that isn't owned or pointed at this ALB). The ALB's default listener rule 404s any request whose `Host` header doesn't match a configured rule.
**Fix**: made `ingress.host` empty by default in all three `values-<env>.yaml` and changed `helm/task-tracker/templates/ingress.yaml` to omit the `host:` field entirely when unset — an empty/omitted host produces a catch-all rule matching any `Host` header, including the raw ALB DNS name.

### Browser: "This site can't be reached ... ERR_CONNECTION_TIMED_OUT"

**Cause**: the browser defaulted to `https://` (port 443), but the ALB only has an HTTP:80 listener (TLS is explicitly out of scope for this project). AWS security groups silently drop non-matching traffic rather than reject it, which surfaces as a timeout, not "connection refused."
**Fix**: use `http://` explicitly. No infra change — documented as a known limitation.

### CI's `helm upgrade --create-namespace` fails with a 403

```
Error: 1 error occurred:
	* namespaces is forbidden: User "arn:aws:iam::246312965731:user/myapp-github-actions-ci" cannot create resource "namespaces" in API group "" at the cluster scope
```

**Cause**: `Namespace` is a cluster-scoped Kubernetes object. The CI user's `AmazonEKSEditPolicy` access policy was associated with `access-scope type=namespace,namespaces=myapp-dev` — which only grants permissions on resources *inside* that namespace, not on the `Namespace` object type itself (confirmed: `kubectl auth can-i get namespaces --as=<ci-user-arn>` → `no`, even after the namespace already existed).
**Fix**: pre-created the namespace once by hand (`kubectl create namespace myapp-dev`, using broader admin credentials) and removed `--create-namespace` from `app-cd.yml`'s `helm upgrade` command — CI never needs cluster-scoped Namespace permissions again.

### CloudWatch log groups exist but are always empty

```bash
$ aws logs describe-log-streams --log-group-name /aws/containerinsights/myapp-dev/application
{"logStreams": []}
```

**Cause**: `modules/cloudwatch` created the destination log groups in Terraform, but nothing was installed to actually collect and ship container stdout/stderr into them — the EKS control-plane log group (`/aws/eks/myapp-dev/cluster`) worked because that's a built-in AWS feature needing no agent; application logs are not.
**Fix**: added the `amazon-cloudwatch-observability` EKS managed add-on (`modules/eks/main.tf`) — deploys Fluent Bit + CloudWatch Agent as DaemonSets via a dedicated IRSA role. Verified afterward: real log streams with recent `lastEventTimestamp` values appeared within minutes.

### Prometheus/Grafana PVCs stuck `Pending` forever

```
Warning  FailedBinding  persistentvolumeclaim/kube-prometheus-stack-grafana
no persistent volumes available for this claim and no storage class is set
```

**Cause**: the cluster's only `StorageClass` was `gp2` (legacy in-tree `kubernetes.io/aws-ebs` provisioner), and it was never marked as the cluster default — despite `modules/eks` already installing the `aws-ebs-csi-driver` addon. PVCs with no explicit `storageClassName` (like this chart's) had nowhere to bind.
**Fix**: added a `kubernetes_storage_class_v1` resource (`modules/monitoring/main.tf`) named `gp3`, provisioner `ebs.csi.aws.com`, annotated `storageclass.kubernetes.io/is-default-class: "true"`. The stuck Helm release was `tainted` after a timeout; re-running `terraform apply` (with `helm_release` `timeout` bumped from the 300s default to `900`) replaced it cleanly.

### `ServiceMonitor` access denied for the CI user

```
Error: UPGRADE FAILED: Unable to continue with update: could not get information about the resource ServiceMonitor "task-tracker" in namespace "myapp-dev": servicemonitors.monitoring.coreos.com "task-tracker" is forbidden: User "arn:aws:iam::246312965731:user/myapp-github-actions-ci" cannot get resource "servicemonitors" in API group "monitoring.coreos.com" in the namespace "myapp-dev"
```

**Cause**: AWS's `AmazonEKSEditPolicy` mirrors Kubernetes' built-in `edit` ClusterRole, which does not cover custom resources (CRDs) like `ServiceMonitor` unless a controller explicitly aggregates them into it — the Prometheus Operator doesn't.
**Fix**: applied a narrowly-scoped `Role` + `RoleBinding` (verbs `get/list/watch/create/update/patch/delete` on `servicemonitors`/`podmonitors`/`prometheusrules` only, in `myapp-dev` only) bound to the CI user's exact Kubernetes username (`arn:aws:iam::246312965731:user/myapp-github-actions-ci` — confirmed via `aws eks describe-access-entry`), applied directly via `kubectl`, not Terraform.

### Grafana's new IRSA role doesn't work until the pod restarts

**Cause**: updating the Grafana ServiceAccount's `eks.amazonaws.com/role-arn` annotation via `terraform apply` doesn't affect an already-running pod — the EKS Pod Identity webhook only injects `AWS_ROLE_ARN`/`AWS_WEB_IDENTITY_TOKEN_FILE` at pod **creation** time.
**Fix**: `kubectl rollout restart deployment kube-prometheus-stack-grafana -n monitoring` after any IRSA/ServiceAccount annotation change.

### CloudWatch Logs Insights query: `MalformedQueryException`

```
MalformedQueryException: Invalid syntax while using query definition snippets: unexpected symbol found fields at line 1 and position 0
```

**Cause**: a test query to Grafana's `/api/ds/query` endpoint had an empty `logGroups` array and no `queryString` field.
**Fix**: supplied a real log group ARN and a proper query string (`fields @timestamp, @message | sort @timestamp desc | limit 5`) — the error was in the test call, not a permissions problem (confirmed once fixed: `"status":200` with real matched records).

### CloudWatch datasource's region picker returns 403

```
level=error msg="Failed to get regions: " error="UnauthorizedOperation: You are not authorized to perform this operation. User: arn:aws:sts::246312965731:assumed-role/myapp-dev-grafana-cloudwatch-irsa/... is not authorized to perform: ec2:DescribeRegions ..."
```

**Cause**: neither `CloudWatchReadOnlyAccess` nor `CloudWatchLogsReadOnlyAccess` includes `ec2:DescribeRegions`, which the CloudWatch datasource's UI region-picker calls — cosmetic, doesn't block actual log/metric queries.
**Fix**: added a scoped inline `aws_iam_role_policy` granting just `ec2:DescribeRegions` (`modules/monitoring/main.tf`).

### A dropdown's `onchange` handler silently does nothing

**Cause**: Helmet's default Content-Security-Policy sets `script-src-attr: 'none'`, which blocks inline event-handler attributes like `onchange="this.form.submit()"` — confirmed via the actual response header (`Content-Security-Policy: ...script-src-attr 'none'...`).
**Fix**: replaced the inline handler in `app/src/views/tasks/show.ejs` with a plain, always-visible `<button type="submit">Update</button>` — no CSP exception needed, no JS dependency at all.

### Grafana shows "Error code: Out of Memory"

**Cause**: this is a **browser** error (`ERR_OUT_OF_MEMORY`), not a Grafana server error. Investigation ruled out every server-side cause: pod had `0` restarts, no `OOMKilled`/eviction events cluster-wide, both nodes reported `MemoryPressure: False`, nothing in Grafana's own container logs. Most likely trigger: an unbounded CloudWatch Logs Insights query (wide time range, no `limit`) returning enough rows to exhaust the browser tab's memory while rendering them.
**Fix**: no infra change; reload the tab, and add `| limit 100` plus a narrower time range to Logs Insights queries.

---

## Project Highlights

- **No static AWS credentials anywhere in the app or its pods** — every AWS call (S3, Secrets Manager, RDS credentials) goes through IRSA; the only static AWS credentials in this entire project are the CI user's, stored as GitHub secrets.
- **Dual EKS authentication verified working**, not just configured — both `kubectl get configmap aws-auth -n kube-system` and `aws eks list-access-entries` return real data simultaneously.
- **Dashboards as code** — both Grafana dashboards (`modules/monitoring/dashboards/*.json`) are committed JSON, auto-imported via a labeled `ConfigMap` and Grafana's sidecar, not manually clicked together in the UI.
- **Every CI/CD action is AWS-native** — `azure/setup-kubectl` and `azure/setup-helm` were identified and replaced with plain `curl` installs from the upstream Kubernetes/Helm release endpoints, specifically because this pipeline targets AWS only.
- **Signed commit history** — every commit in this repository is SSH-signed and shows "Verified" on GitHub (`git log --show-signature`), including 5 pre-existing commits that were retroactively re-signed via an interactive rebase.
- **Real incident count**: 15 distinct infrastructure/application problems were hit and fixed while building this out (see Troubleshooting) — none of them hypothetical.

---

## Resources

- [terraform-aws-modules/eks](https://github.com/terraform-aws-modules/terraform-aws-eks)
- [terraform-aws-modules/vpc](https://github.com/terraform-aws-modules/terraform-aws-vpc)
- [terraform-aws-modules/iam (IRSA submodule)](https://github.com/terraform-aws-modules/terraform-aws-iam/tree/master/modules/iam-role-for-service-accounts-eks)
- [AWS EKS documentation](https://docs.aws.amazon.com/eks/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [kube-prometheus-stack Helm chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [Prometheus Operator / ServiceMonitor](https://prometheus-operator.dev/docs/getting-started/design/)
- [Grafana CloudWatch datasource](https://grafana.com/docs/grafana/latest/datasources/aws-cloudwatch/)
- [prom-client (Node.js)](https://github.com/siimon/prom-client)
- [node-postgres (`pg`)](https://node-postgres.com/)
- [Helm](https://helm.sh/docs/)
- [GitHub Actions](https://docs.github.com/en/actions)

---

## Contributing

Open a pull request against `main` at `github.com/lerisngwa-tech/DevOps-Project` with a clear description of what changed and why; `app-ci.yml` runs automatically on any PR touching `app/**`.

---

## Author

Repository: [github.com/lerisngwa-tech/DevOps-Project](https://github.com/lerisngwa-tech/DevOps-Project)
