# =============================================================================
# All naming/region constraints from the exam brief's Section 1 table are
# pinned here as variable defaults. They're variables (not hardcoded in every
# module) so there's exactly one place to look if anything needs to change,
# but the defaults ARE the graded values — don't override them.
# =============================================================================

variable "aws_region" {
  description = "AWS region — fixed by exam brief"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name — fixed by exam brief"
  type        = string
  default     = "project-bedrock-cluster"
}

variable "vpc_name" {
  description = "VPC Name tag — fixed by exam brief"
  type        = string
  default     = "project-bedrock-vpc"
}

variable "app_namespace" {
  description = "Kubernetes namespace for the retail app — fixed by exam brief"
  type        = string
  default     = "retail-app"
}

variable "dev_iam_user_name" {
  description = "Read-only developer IAM user — fixed by exam brief"
  type        = string
  default     = "bedrock-dev-view"
}

variable "assets_bucket_name" {
  description = "S3 bucket for uploaded assets. Must be globally unique, lowercase, no slashes."
  type        = string
  default     = "bedrock-assets-alt-soe-tin-025-0379"
}

variable "lambda_function_name" {
  description = "Asset-processor Lambda name — fixed by exam brief"
  type        = string
  default     = "bedrock-asset-processor"
}

variable "project_tag" {
  description = "Mandatory tag applied to every resource"
  type        = string
  default     = "tinyuka-2025-capstone"
}

# -----------------------------------------------------------------------------
# EKS version — pinned to the oldest version in STANDARD support as of the
# date this was checked (see README.md "Version decisions" for the source
# and date). Re-verify this against the EKS release calendar before you
# apply, since support windows move — this is not a "set once" value.
# -----------------------------------------------------------------------------
variable "eks_version" {
  description = "Kubernetes version for EKS control plane and nodes"
  type        = string
  default     = "1.34"
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability zones to spread subnets across (exactly 2, per brief minimum)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

# -----------------------------------------------------------------------------
# Node group sizing — deliberately small/cheap; this is a capstone exam,
# not a production workload. Adjust only if pods are failing to schedule.
# -----------------------------------------------------------------------------
variable "node_instance_types" {
  description = "EC2 instance types for the EKS managed node group"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_group_desired_size" {
  type    = number
  default = 2
}

variable "node_group_min_size" {
  type    = number
  default = 2
}

variable "node_group_max_size" {
  type    = number
  default = 4
}

# -----------------------------------------------------------------------------
# RDS sizing — smallest viable instance class per brief's cost guidance.
# -----------------------------------------------------------------------------
variable "rds_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "rds_backup_retention_days" {
  description = "Automated backup retention window in days. Bonus 5.5 requires > 0."
  type        = number
  default     = 7
}

# -----------------------------------------------------------------------------
# Budget guardrail
# -----------------------------------------------------------------------------
variable "budget_limit_usd" {
  type    = number
  default = 20
}

variable "budget_alert_email" {
  description = "Email address to receive AWS Budget alerts"
  type        = string
  # No default — must be supplied via terraform.tfvars or -var, since this
  # is personal to you and shouldn't be hardcoded in a shared default.
}
