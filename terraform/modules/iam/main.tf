# -----------------------------------------------------------------------------
# Developer User
# -----------------------------------------------------------------------------
resource "aws_iam_user" "dev" {
  name = var.dev_iam_user_name
}

resource "aws_iam_user_policy_attachment" "readonly" {
  user       = aws_iam_user.dev.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# -----------------------------------------------------------------------------
# Console Credentials & Access Key
# -----------------------------------------------------------------------------
resource "aws_iam_access_key" "dev" {
  user = aws_iam_user.dev.name
}

resource "aws_iam_user_login_profile" "dev" {
  user                    = aws_iam_user.dev.name
  password_reset_required = false
}

# -----------------------------------------------------------------------------
# EKS Access Entry (Namespaced View)
# -----------------------------------------------------------------------------
resource "aws_eks_access_entry" "dev" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_user.dev.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "dev_view" {
  cluster_name  = var.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
  principal_arn = aws_iam_user.dev.arn

  access_scope {
    type       = "namespace"
    namespaces = [var.app_namespace]
  }
}

# -----------------------------------------------------------------------------
# S3 PutObject Permission for Dev User
# -----------------------------------------------------------------------------
resource "aws_iam_user_policy" "s3_put" {
  name = "s3-put-assets"
  user = aws_iam_user.dev.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["s3:PutObject"]
        Effect   = "Allow"
        Resource = "arn:aws:s3:::${var.assets_bucket_name}/*"
      },
    ]
  })
}

# -----------------------------------------------------------------------------
# IRSA: External Secrets Operator
# -----------------------------------------------------------------------------
module "eso_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30"

  role_name = "bedrock-eso-role"

  oidc_providers = {
    ex = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["external-secrets:external-secrets"]
    }
  }

  role_policy_arns = {
    secrets = aws_iam_policy.eso.arn
  }
}

resource "aws_iam_policy" "eso" {
  name        = "bedrock-eso-policy"
  description = "Policy for External Secrets Operator to access RDS secrets"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.catalog_secret_name}-*",
          "arn:aws:secretsmanager:${var.aws_region}:*:secret:${var.orders_secret_name}-*"
        ]
      },
    ]
  })
}

# -----------------------------------------------------------------------------
# IRSA: Carts Service
# -----------------------------------------------------------------------------
module "carts_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30"

  role_name = "bedrock-carts-role"

  oidc_providers = {
    ex = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["${var.app_namespace}:carts"]
    }
  }

  role_policy_arns = {
    dynamodb = aws_iam_policy.carts.arn
  }
}

resource "aws_iam_policy" "carts" {
  name        = "bedrock-carts-policy"
  description = "Policy for Carts service to access DynamoDB"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "dynamodb:Query",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchWriteItem"
        ]
        Effect   = "Allow"
        Resource = var.carts_dynamodb_arn
      },
    ]
  })
}

# -----------------------------------------------------------------------------
# Lambda Execution Role
# -----------------------------------------------------------------------------
resource "aws_iam_role" "lambda" {
  name = "bedrock-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_s3" {
  name = "bedrock-lambda-s3"
  role = aws_iam_role.lambda.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["s3:GetObject"]
        Effect   = "Allow"
        Resource = "arn:aws:s3:::${var.assets_bucket_name}/*"
      },
    ]
  })
}
