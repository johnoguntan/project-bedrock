variable "app_namespace" { type = string }
variable "aws_region" { type = string }
variable "catalog_secret_name" { type = string }
variable "orders_secret_name" { type = string }
variable "catalog_db_endpoint" { type = string }
variable "orders_db_endpoint" { type = string }
variable "carts_dynamodb_table" { type = string }
variable "carts_irsa_role_arn" { type = string }

variable "tls_dns_name" {
  description = "DNS name (or wildcard) the ACM cert covers. Defaults to nip.io magic DNS since the exam doesn't require a real owned domain. Swap for a real domain + DNS-validated ACM cert if you have one."
  type        = string
  default     = "*.nip.io"
}
