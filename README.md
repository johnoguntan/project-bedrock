# Project Bedrock

InnovateMart's first production-grade EKS deployment — Tinyuka Third Semester Exam capstone. Provisions a VPC, EKS cluster, managed data layer (RDS + DynamoDB), and deploys the [aws-containers/retail-store-sample-app](https://github.com/aws-containers/retail-store-sample-app) behind an ALB, with observability, a scoped read-only developer identity, and an S3→Lambda event pipeline.

Architecture diagram: [`docs/architecture.png`](docs/architecture.png) ([source SVG](docs/architecture.svg)).

## Repo layout

```
terraform/
  bootstrap/        one-time: creates the S3 state bucket (local state)
  modules/
    vpc/             VPC, public/private subnets, single NAT gateway
    eks/             EKS cluster + managed node group, control-plane logging, access entries
    data/            RDS MySQL (catalog), RDS PostgreSQL (orders), DynamoDB (carts), Secrets Manager
    iam/             bedrock-dev-view user, IRSA roles (ESO, carts, lambda)
    alb-controller/  AWS Load Balancer Controller (helm + IRSA)
    cluster-autoscaler/  Cluster Autoscaler (bonus 5.3)
    observability/   CloudWatch Observability EKS add-on
    serverless/      S3 bucket, Lambda, event notification
    app/             namespace, External Secrets Operator, retail-store-sample-app helm release, TLS cert (bonus 5.2)
  main.tf, outputs.tf, variables.tf, providers.tf, versions.tf, backend.tf
  github_oidc.tf     scoped IAM role for GitHub Actions OIDC
lambda/app.py        asset-processor Lambda source
k8s/network-policies/  NetworkPolicy manifests (bonus 5.4)
.github/workflows/terraform.yml
grading.json          generated after apply — see "Grading data" below
```

## Prerequisites

- Terraform ≥ 1.11.0 (required for native S3 backend locking)
- AWS CLI configured with credentials that can create IAM/EKS/RDS/VPC/S3/Lambda resources
- `kubectl`, `helm` (for manual verification after apply)
- An AWS account in `us-east-1`

## 1. Bootstrap the remote state bucket (one time)

The root config's S3 backend needs a bucket to exist before `terraform init` can use it — so a separate, tiny config creates just that bucket with local state:

```bash
cd terraform/bootstrap
terraform init
terraform apply -var="state_bucket_name=bedrock-tfstate-<your-unique-suffix>"
```

Note the bucket name from the output.

## 2. Configure the root module

```bash
cd terraform
cp backend.hcl.example backend.hcl        # fill in the bucket name from step 1
cp terraform.tfvars.example terraform.tfvars  # fill in your email for budget alerts

terraform init -backend-config=backend.hcl
```

`terraform.tfvars` and `backend.hcl` are both gitignored — never commit them (not because they're secret in this case, but to keep environment-specific values out of version control).

## 3. Deploy

```bash
terraform plan
terraform apply
```

This provisions everything: VPC, EKS cluster, RDS instances, DynamoDB table, the retail-store-sample-app (via Helm, wired to the managed data layer), the AWS Load Balancer Controller, Cluster Autoscaler, CloudWatch Observability add-on, the S3/Lambda asset pipeline, the `bedrock-dev-view` IAM user, and the AWS Budget. Expect 15–20 minutes for the EKS cluster and node group alone.

### Getting the store URL

The ALB is provisioned by the AWS Load Balancer Controller at reconcile time (not by Terraform directly), so its address only exists once the controller has processed the Ingress:

```bash
aws eks update-kubeconfig --name project-bedrock-cluster --region us-east-1
kubectl get ingress -n retail-app
```

The `ADDRESS` column is the ALB's public DNS name. Open `http://<that-address>/` for HTTP, or `https://<that-address>/` for HTTPS (see the TLS note below — the certificate is self-signed, so your browser will warn on the first visit; that's expected, not a bug).

## CI/CD

GitHub Actions (`.github/workflows/terraform.yml`) runs on every PR and push to `main`, authenticating via OIDC (no long-lived AWS keys in the repo).

**One-time repo setup**, in Settings → Secrets and variables → Actions:

| Type | Name | Value |
|---|---|---|
| Secret | `AWS_ACCOUNT_ID` | your 12-digit account ID |
| Secret | `BUDGET_ALERT_EMAIL` | email for the AWS Budget alert |
| Variable | `TF_STATE_BUCKET` | the bucket name from bootstrap step 1 |

**Pull request** → `terraform plan` runs and the output is posted (or updated in-place on subsequent pushes) as a PR comment.
**Merge to `main`** → `terraform apply -auto-approve` runs against live infrastructure. Review every PR's plan comment carefully before merging — there's no manual approval gate in front of apply.

The GitHub Actions role (`bedrock-github-actions-role`, defined in `github_oidc.tf`) is scoped to the specific AWS services this project touches, not `AdministratorAccess`.

## Developer access — `bedrock-dev-view`

After apply, credentials are in Terraform state as sensitive outputs on the `iam` module (never surfaced at root — see "Secrets hygiene" below). Retrieve them once, right after apply:

```bash
terraform output -raw dev_access_key_id
terraform output -raw dev_secret_access_key
terraform output -raw dev_console_password
```

Verify the scope:

```bash
aws configure --profile bedrock-dev   # paste the access key/secret above
aws eks update-kubeconfig --name project-bedrock-cluster --region us-east-1 --profile bedrock-dev
kubectl --context <ctx> get pods -n retail-app        # should succeed
kubectl --context <ctx> delete pod <any-pod> -n retail-app   # should be denied (Forbidden)
```

**Rotate or deactivate this access key once grading is complete** — it's a real, working credential.

## Observability

- Control plane logs (api, audit, authenticator, controllerManager, scheduler) → CloudWatch Log Groups, enabled in `modules/eks`.
- Container/application logs → Amazon CloudWatch Observability EKS add-on (`modules/observability`), IRSA-scoped.
- Check in the console under CloudWatch → Log groups → `/aws/eks/project-bedrock-cluster/*` and the `/aws/containerinsights/...` groups.

## Serverless asset pipeline

Upload a file to `bedrock-assets-<suffix>` (e.g. using the `bedrock-dev-view` credentials, which have `s3:PutObject` on this bucket only) and check CloudWatch Logs for the `bedrock-asset-processor` Lambda — it logs `Image received: <filename>`.

```bash
aws s3 cp ./test.jpg s3://bedrock-assets-<suffix>/test.jpg --profile bedrock-dev
aws logs tail /aws/lambda/bedrock-asset-processor --follow
```

## Bonus objectives

- **5.1 Helm-based deployment** — the app is already deployed via the upstream Helm chart (`terraform/modules/app/main.tf`, `helm_release.retail_app`), with `values` overriding the data layer to point at RDS/DynamoDB instead of in-cluster databases.
- **5.2 TLS/ACM** — `terraform/modules/app/tls.tf` generates a self-signed certificate and imports it into ACM, then the ALB terminates HTTPS with it (`alb.ingress.kubernetes.io/certificate-arn`, `ssl-redirect: 443`). This satisfies "a certificate from ACM" but is **not a trusted cert** — nip.io isn't a domain you control in Route 53, so DNS validation isn't possible without owning a real domain. If you have one, swap in a real `aws_acm_certificate` with `validation_method = "DNS"`.
- **5.3 Cluster Autoscaler** — installed in `terraform/modules/cluster-autoscaler`. To demonstrate a scale-up:
  ```bash
  kubectl scale deployment/ui -n retail-app --replicas=15
  kubectl -n kube-system logs -f deployment/cluster-autoscaler | grep -i "scale-up"
  kubectl get nodes -w   # watch a new node join
  ```
  Document the before/after node count and how long the new node took to join in your submission.
- **5.4 NetworkPolicies** — `k8s/network-policies/`. Apply with `kubectl apply -f k8s/network-policies/` and see that directory's README for the allow-list and verification commands. **Check pod label selectors match your deployed chart version before applying** (see the caveat in that README).
- **5.5 Resilience**
  - Pod self-healing: `kubectl get pods -n retail-app -o wide`, then `kubectl delete pod <ui-pod> -n retail-app`, then re-run `get pods` and time how long the replacement takes `Running`. Document both snapshots.
  - Automated backups: both RDS instances have `backup_retention_period = 7` days (`var.rds_backup_retention_days` in `terraform/variables.tf`).

## Secrets hygiene

Root outputs (`terraform/outputs.tf`) are intentionally limited to the 5 required non-sensitive values: `cluster_endpoint`, `cluster_name`, `region`, `vpc_id`, `assets_bucket_name`. `terraform output -json` prints sensitive values in full regardless of `sensitive = true`, so nothing sensitive is exposed at the root module — DB passwords and IAM credentials only exist as outputs on the `data` and `iam` child modules, read individually with `-raw` as shown above.

## Grading data

After a successful apply:

```bash
cd terraform
terraform output -json > ../grading.json
```

Commit `grading.json` at the repo root. It will only contain the 5 required values — confirm this before committing (`cat grading.json`).

## Teardown

Order matters — destroy the app/cluster before the state bucket exists to be destroyed:

```bash
cd terraform
terraform destroy
```

Terraform will remove the VPC, EKS cluster and node group, RDS instances (final snapshots are skipped — `skip_final_snapshot = true`, so there is no post-destroy snapshot to separately delete), DynamoDB table, Lambda, IAM resources, budget, and the Helm releases (ALB Controller, Cluster Autoscaler, External Secrets, retail-store-sample-app).

**Manual cleanup Terraform won't do for you:**

1. **S3 object deletion** — `aws_s3_bucket.assets` will fail to delete if it still has objects in it (any test uploads from the Lambda verification step). Empty it first:
   ```bash
   aws s3 rm s3://bedrock-assets-<suffix> --recursive
   ```
2. **CloudWatch Log Groups** — EKS control-plane and container log groups are not deleted by `terraform destroy` (they're created by AWS-managed resources outside direct Terraform ownership in some cases, or may be retained by design). Check and remove manually if you don't want to keep paying for log storage:
   ```bash
   aws logs describe-log-groups --log-group-name-prefix "/aws/eks/project-bedrock-cluster" --region us-east-1
   aws logs delete-log-group --log-group-name <name> --region us-east-1
   ```
3. **The Terraform state bucket** (`terraform/bootstrap`) has `prevent_destroy = true` and versioning enabled — it will *not* be removed by `terraform destroy` in either config, on purpose. If you're fully done and want it gone: remove the `prevent_destroy` lifecycle block, empty all object versions, then `terraform destroy` in `terraform/bootstrap/`.
4. **`bedrock-dev-view` access key** — deactivate or delete once grading is complete (see "Developer access" above); it's a live credential Terraform will happily destroy along with everything else, but do this *before* you tear the rest down if a grader is still actively using it.
5. **ACM self-signed certificate** — destroyed along with the `app` module; no separate action needed.

## Cost guardrails already in place

- Single NAT Gateway (not one per AZ)
- Single-AZ, `db.t4g.micro` RDS instances for both databases
- AWS Budget (`terraform/main.tf`) at `$20`/month with an email alert, scoped to `Project: tinyuka-2025-capstone`
- Small EKS node group (`t3.medium`, 2–4 nodes)

Remember to run `terraform destroy` (plus the manual cleanup above) when you're not actively working on this — EKS, NAT, RDS, and ALBs all bill continuously while running.
