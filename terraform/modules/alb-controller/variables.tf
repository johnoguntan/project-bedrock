variable "cluster_name" {
  description = "EKS cluster name the controller will manage ingress for"
  type        = string
}

variable "oidc_provider_arn" {
  description = "OIDC provider ARN for the EKS cluster (for IRSA)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID the cluster runs in"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}
