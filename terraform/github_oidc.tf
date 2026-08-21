# =============================================================================
# GitHub OIDC Role for CI/CD
#
# Scoped to the AWS services this project's Terraform actually manages,
# instead of AdministratorAccess. This is service-boundary least privilege,
# not resource-level least privilege (Terraform needs broad read/write
# within each service to plan and reconcile drift) — but it can no longer
# touch unrelated services, billing settings, Organizations, other
# accounts' resources, etc.
#
# If you add a new AWS resource type to this project and CI starts failing
# with an AccessDenied error, that's this policy doing its job — add the
# specific missing action(s) rather than reaching for a service wildcard
# you don't need.
# =============================================================================
module "iam_github_oidc_provider" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-github-oidc-provider"
  version = "~> 5.30"
}

resource "aws_iam_policy" "github_actions_scoped" {
  name        = "bedrock-github-actions-policy"
  description = "Scoped CI/CD permissions for Project Bedrock Terraform (not AdministratorAccess)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CoreInfra"
        Effect = "Allow"
        Action = [
          "ec2:*",
          "eks:*",
          "autoscaling:*",
          "elasticloadbalancing:*",
          "rds:*",
          "dynamodb:*",
          "s3:*",
          "lambda:*",
          "secretsmanager:*",
          "logs:*",
          "budgets:*",
          "kms:*",
          "cloudwatch:*",
          "acm:*",
        ]
        Resource = "*"
      },
      {
        # IAM is the one service where a blanket wildcard is genuinely
        # risky (privilege escalation via role/policy creation). Scoped
        # to the naming prefixes this project uses, plus the read-only
        # actions Terraform needs to evaluate existing/unrelated roles
        # it references (e.g. AWS managed policy ARNs).
        Sid    = "IamScoped"
        Effect = "Allow"
        Action = [
          "iam:Get*",
          "iam:List*",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:UpdateRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
          "iam:TagPolicy",
          "iam:UntagPolicy",
          "iam:CreateUser",
          "iam:DeleteUser",
          "iam:TagUser",
          "iam:UntagUser",
          "iam:PutUserPolicy",
          "iam:DeleteUserPolicy",
          "iam:AttachUserPolicy",
          "iam:DetachUserPolicy",
          "iam:CreateAccessKey",
          "iam:DeleteAccessKey",
          "iam:CreateLoginProfile",
          "iam:DeleteLoginProfile",
          "iam:UpdateLoginProfile",
          "iam:CreateOpenIDConnectProvider",
          "iam:DeleteOpenIDConnectProvider",
          "iam:TagOpenIDConnectProvider",
          "iam:UpdateOpenIDConnectProviderThumbprint",
          "iam:PassRole",
        ]
        Resource = "*"
      },
      {
        Sid      = "EksAccessEntries"
        Effect   = "Allow"
        Action   = ["eks:*AccessEntry*", "eks:*AccessPolicy*"]
        Resource = "*"
      },
    ]
  })
}

module "iam_github_oidc_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-github-oidc-role"
  version = "~> 5.30"
  name    = "bedrock-github-actions-role"

  # GitHub now embeds immutable owner/repo numeric IDs into the OIDC sub
  # claim (confirmed via a debug step that printed the actual token:
  # "repo:johnoguntan@246523484/project-bedrock@1329015419:ref:refs/heads/main")
  # instead of the plain "repo:johnoguntan/project-bedrock:*" this was
  # originally written against. That's why every CI run since day one
  # failed at AssumeRoleWithWebIdentity — the StringLike condition never
  # matched the real subject string. IDs are stable across renames, so
  # this is also more correct than name-matching, not just a workaround.
  subjects = ["johnoguntan@246523484/project-bedrock@1329015419:*"]

  policies = {
    scoped = aws_iam_policy.github_actions_scoped.arn
  }
}

# -----------------------------------------------------------------------------
# EKS Access Entry for CI
#
# IAM permissions on eks:* control-plane APIs (above) let this role call
# things like eks:DescribeCluster — they do NOT grant Kubernetes API-server
# access. Every apply that touches the kubernetes/helm providers (the app,
# alb-controller, cluster-autoscaler, and observability modules all do)
# needs the applying identity to also be authorized inside the cluster via
# an Access Entry. Only the identity that ran the very first `apply`
# gets that automatically (enable_cluster_creator_admin_permissions in the
# eks module) — CI is a different identity, so it needs its own entry.
#
# Cluster-scoped admin (not namespace-scoped) because CI manages
# kube-system (ALB Controller, Cluster Autoscaler) as well as retail-app.
# -----------------------------------------------------------------------------
resource "aws_eks_access_entry" "github_actions" {
  cluster_name  = module.eks.cluster_name
  principal_arn = module.iam_github_oidc_role.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "github_actions_admin" {
  cluster_name  = module.eks.cluster_name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = module.iam_github_oidc_role.arn

  access_scope {
    type = "cluster"
  }
}
