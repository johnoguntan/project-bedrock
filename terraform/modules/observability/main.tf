data "aws_iam_policy" "cwa" {
  arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

data "aws_iam_policy" "xray" {
  arn = "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess"
}

module "cwo_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30"

  role_name = "bedrock-cwo-role"

  oidc_providers = {
    ex = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["amazon-cloudwatch:cloudwatch-agent"]
    }
  }

  role_policy_arns = {
    cwa  = data.aws_iam_policy.cwa.arn
    xray = data.aws_iam_policy.xray.arn
  }
}

resource "aws_eks_addon" "cwo" {
  cluster_name                = var.cluster_name
  addon_name                  = "amazon-cloudwatch-observability"
  service_account_role_arn    = module.cwo_irsa.iam_role_arn
  resolve_conflicts_on_update = "PRESERVE"
}
