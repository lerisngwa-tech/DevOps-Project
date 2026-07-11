ENV ?= dev
AWS_REGION ?= us-east-1
TF_DIR := ../envs/$(ENV)
TAG := $(shell git rev-parse --short HEAD 2>/dev/null || date +%s)

tf-output = $(shell cd $(TF_DIR) && terraform output -raw $(1))

.PHONY: build push deploy release

build:
	docker build -t task-tracker:$(TAG) .

push: build
	$(eval REPO := $(call tf-output,ecr_repository_url))
	aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(REPO)
	docker tag task-tracker:$(TAG) $(REPO):$(TAG)
	docker push $(REPO):$(TAG)

deploy: push
	$(eval REPO := $(call tf-output,ecr_repository_url))
	$(eval S3_BUCKET := $(call tf-output,app_bucket_name))
	$(eval S3_ROLE := $(call tf-output,app_bucket_irsa_role_arn))
	$(eval DB_SECRET_ARN := $(call tf-output,db_secret_arn))
	$(eval DB_ROLE := $(call tf-output,db_secret_irsa_role_arn))
	helm upgrade --install task-tracker ./chart/task-tracker \
	  -f chart/task-tracker/values-$(ENV).yaml \
	  --set image.repository=$(REPO) \
	  --set image.tag=$(TAG) \
	  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$(S3_ROLE) \
	  --set env.s3BucketName=$(S3_BUCKET) \
	  --set env.dbSecretArn=$(DB_SECRET_ARN) \
	  --set env.dbSecretRoleArn=$(DB_ROLE) \
	  --namespace default

release: deploy
