# -----------------------------------------------------------------------------
# Namespaces
# -----------------------------------------------------------------------------
resource "kubernetes_namespace" "app" {
  metadata {
    name = var.app_namespace
  }
}

resource "kubernetes_namespace" "eso" {
  metadata {
    name = "external-secrets"
  }
}

# -----------------------------------------------------------------------------
# External Secrets Operator (ESO)
# -----------------------------------------------------------------------------
resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  namespace  = kubernetes_namespace.eso.metadata[0].name
  version    = "0.9.11"

  set {
    name  = "installCRDs"
    value = "true"
  }
}

# -----------------------------------------------------------------------------
# SecretStore and ExternalSecrets (Manifests)
# -----------------------------------------------------------------------------
resource "kubernetes_manifest" "cluster_secret_store" {
  depends_on = [helm_release.external_secrets]
  
  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "aws-secretsmanager"
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.aws_region
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = "external-secrets"
                namespace = kubernetes_namespace.eso.metadata[0].name
              }
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_manifest" "catalog_secret" {
  depends_on = [kubernetes_manifest.cluster_secret_store]

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "catalog-db-secret"
      namespace = kubernetes_namespace.app.metadata[0].name
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "aws-secretsmanager"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "catalog-db-secret"
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "username"
          remoteRef = {
            key      = var.catalog_secret_name
            property = "username"
          }
        },
        {
          secretKey = "password"
          remoteRef = {
            key      = var.catalog_secret_name
            property = "password"
          }
        }
      ]
    }
  }
}

resource "kubernetes_manifest" "orders_secret" {
  depends_on = [kubernetes_manifest.cluster_secret_store]

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "orders-db-secret"
      namespace = kubernetes_namespace.app.metadata[0].name
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "aws-secretsmanager"
        kind = "ClusterSecretStore"
      }
      target = {
        name           = "orders-db-secret"
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "username"
          remoteRef = {
            key      = var.orders_secret_name
            property = "username"
          }
        },
        {
          secretKey = "password"
          remoteRef = {
            key      = var.orders_secret_name
            property = "password"
          }
        }
      ]
    }
  }
}

# -----------------------------------------------------------------------------
# Retail Store Sample App (Helm Chart)
# -----------------------------------------------------------------------------
resource "helm_release" "retail_app" {
  name       = "retail-store"
  repository = "https://aws-containers.github.io/retail-store-sample-app/"
  chart      = "retail-store-sample-app"
  namespace  = kubernetes_namespace.app.metadata[0].name
  version    = "0.8.1" # Or latest

  depends_on = [
    kubernetes_manifest.catalog_secret,
    kubernetes_manifest.orders_secret
  ]

  # Configuration for Catalog (MySQL)
  set {
    name  = "catalog.db.type"
    value = "mysql"
  }
  set {
    name  = "catalog.db.endpoint"
    value = var.catalog_db_endpoint
  }
  set {
    name  = "catalog.db.name"
    value = "catalog"
  }
  set {
    name  = "catalog.db.secretName"
    value = "catalog-db-secret"
  }

  # Configuration for Orders (PostgreSQL)
  set {
    name  = "orders.db.type"
    value = "postgres"
  }
  set {
    name  = "orders.db.endpoint"
    value = var.orders_db_endpoint
  }
  set {
    name  = "orders.db.name"
    value = "orders"
  }
  set {
    name  = "orders.db.secretName"
    value = "orders-db-secret"
  }

  # Configuration for Carts (DynamoDB)
  set {
    name  = "carts.db.type"
    value = "dynamodb"
  }
  set {
    name  = "carts.db.dynamoTableName"
    value = var.carts_dynamodb_table
  }
  set {
    name  = "carts.serviceAccount.name"
    value = "carts"
  }
  set {
    name  = "carts.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.carts_irsa_role_arn
  }

  # Configuration for UI Ingress
  set {
    name  = "ui.ingress.enabled"
    value = "true"
  }
  set {
    name  = "ui.ingress.annotations.kubernetes\\.io/ingress\\.class"
    value = "alb"
  }
  set {
    name  = "ui.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/scheme"
    value = "internet-facing"
  }
  set {
    name  = "ui.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/target-type"
    value = "ip"
  }

  # TLS termination at the ALB (Bonus 5.2). See tls.tf for the cert.
  set {
    name  = "ui.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/certificate-arn"
    value = aws_acm_certificate.ui.arn
  }
  set {
    name  = "ui.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/listen-ports"
    value = "[{\"HTTP\":80},{\"HTTPS\":443}]"
    type  = "string"
  }
  set {
    name  = "ui.ingress.annotations.alb\\.ingress\\.kubernetes\\.io/ssl-redirect"
    value = "443"
  }
}
