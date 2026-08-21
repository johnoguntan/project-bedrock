# =============================================================================
# Root module wiring. See README.md for the deploy order and prerequisites
# (bootstrap the state bucket first — see terraform/bootstrap/).
# =============================================================================

module "vpc" {
  source = "./modules/vpc"

  vpc_name = var.vpc_name
  vpc_cidr = var.vpc_cidr
  azs      = var.azs
}

module "eks" {
  source = "./modules/eks"

  cluster_name        = var.cluster_name
  cluster_version     = var.eks_version
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  node_instance_types = var.node_instance_types
  node_min_size       = var.node_group_min_size
  node_max_size       = var.node_group_max_size
  node_desired_size   = var.node_group_desired_size
}

module "data" {
  source = "./modules/data"

  vpc_id                 = module.vpc.vpc_id
  private_subnet_ids     = module.vpc.private_subnet_ids
  node_security_group_id = module.eks.node_security_group_id
  db_instance_class      = var.rds_instance_class
  backup_retention_days  = var.rds_backup_retention_days
}

module "iam" {
  source = "./modules/iam"

  dev_iam_user_name   = var.dev_iam_user_name
  app_namespace       = var.app_namespace
  assets_bucket_name  = var.assets_bucket_name
  cluster_name        = module.eks.cluster_name
  oidc_provider_arn   = module.eks.oidc_provider_arn
  carts_dynamodb_arn  = module.data.carts_dynamodb_arn
  catalog_secret_name = module.data.catalog_secret_name
  orders_secret_name  = module.data.orders_secret_name
  aws_region          = var.aws_region
}

module "observability" {
  source = "./modules/observability"

  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
}

module "serverless" {
  source = "./modules/serverless"

  assets_bucket_name   = var.assets_bucket_name
  lambda_function_name = var.lambda_function_name
  lambda_role_arn      = module.iam.lambda_role_arn
}

module "alb_controller" {
  source = "./modules/alb-controller"

  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  vpc_id            = module.vpc.vpc_id
  aws_region        = var.aws_region
}

# Bonus 5.3 — see README "Autoscaling" section for the scale-up demo steps.
module "cluster_autoscaler" {
  source = "./modules/cluster-autoscaler"

  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  aws_region        = var.aws_region
}

module "app" {
  source = "./modules/app"

  app_namespace        = var.app_namespace
  aws_region           = var.aws_region
  catalog_secret_name  = module.data.catalog_secret_name
  orders_secret_name   = module.data.orders_secret_name
  catalog_db_endpoint  = module.data.catalog_db_endpoint
  orders_db_endpoint   = module.data.orders_db_endpoint
  carts_dynamodb_table = module.data.carts_dynamodb_table
  carts_irsa_role_arn  = module.iam.carts_irsa_role_arn
  eso_irsa_role_arn    = module.iam.eso_irsa_role_arn

  # The Ingress created here is useless until the controller that
  # reconciles it exists.
  depends_on = [module.alb_controller]
}

# =============================================================================
# AWS Budget
# =============================================================================
resource "aws_budgets_budget" "capstone" {
  name              = "project-bedrock-budget"
  budget_type       = "COST"
  limit_amount      = var.budget_limit_usd
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = "2026-08-01_00:00"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  cost_filter {
    name = "TagKeyValue"
    values = [
      "user:Project$tinyuka-2025-capstone"
    ]
  }
}
