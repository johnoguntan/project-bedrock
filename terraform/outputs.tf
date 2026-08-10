# =============================================================================
# Root module outputs — pinned to exactly the 5 values required by the exam
# brief (Section 1). Do NOT add anything else here: `terraform output -json`
# (used to produce grading.json) prints sensitive values in full regardless
# of any `sensitive = true` flag, so secrets must never be surfaced at this
# level. IAM credentials, DB passwords, etc. live in the `iam` / `data`
# module outputs only and are never re-exported through the root module.
# =============================================================================

output "cluster_endpoint" {
  description = "EKS control plane API endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "region" {
  description = "AWS region resources were provisioned in"
  value       = var.aws_region
}

output "vpc_id" {
  description = "VPC ID for project-bedrock-vpc"
  value       = module.vpc.vpc_id
}

output "assets_bucket_name" {
  description = "S3 bucket name for the asset-processing pipeline"
  value       = module.serverless.assets_bucket_name
}
