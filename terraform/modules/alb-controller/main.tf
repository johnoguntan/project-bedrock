# =============================================================================
# AWS Load Balancer Controller
#
# Without this, the `ui.ingress.*` values set in the app module's
# helm_release just create an Ingress object that nothing ever reconciles —
# no ALB gets provisioned and the store stays unreachable. This module
# installs the controller itself (latest stable chart) with a scoped IRSA
# role using the upstream AWS-published IAM policy for the controller.
# =============================================================================

# Note: this module intentionally does not create the `kube-system`
# namespace — it always exists by default on EKS.

# -----------------------------------------------------------------------------
# IAM policy — official AWS Load Balancer Controller policy document.
# Pulled from the upstream eks-charts release rather than hand-written,
# since it's long and AWS updates it with new permissions per release.
# -----------------------------------------------------------------------------
data "http" "alb_controller_iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.9.2/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "alb_controller" {
  name        = "bedrock-alb-controller-policy"
  description = "Permissions for the AWS Load Balancer Controller (upstream v2.9.2 policy)"
  policy      = data.http.alb_controller_iam_policy.response_body
}

module "alb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.30"

  role_name = "bedrock-alb-controller-role"

  oidc_providers = {
    ex = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  role_policy_arns = {
    alb_controller = aws_iam_policy.alb_controller.arn
  }
}

# -----------------------------------------------------------------------------
# Controller install
# -----------------------------------------------------------------------------
resource "helm_release" "alb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.9.2" # chart version, tracks controller v2.9.2

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.alb_controller_irsa.iam_role_arn
  }
}
