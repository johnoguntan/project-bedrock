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
# Retail Store Sample App
# -----------------------------------------------------------------------------
# The upstream project retired the single combined Helm chart this
# terraform originally targeted (aws-containers.github.io/retail-store-sample-app
# now 404s) in favor of five separate per-service OCI charts with a very
# different values schema. Under exam time pressure we're deploying the app
# via plain Kubernetes manifests instead (explicitly allowed by the exam
# brief section 4.2 as an alternative to Helm — Helm is bonus 5.1 only).
# See k8s/app/ for the manifests and README.md for how they're applied.
# The namespaces, ESO, and ExternalSecrets above are still used by the
# plain-manifest deployment — only this chart-based resource is removed.
