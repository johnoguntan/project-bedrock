variable "cluster_name" {
  description = "EKS cluster name — must match the ASG discovery tags set in the eks module"
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN for the EKS cluster (for IRSA)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}
