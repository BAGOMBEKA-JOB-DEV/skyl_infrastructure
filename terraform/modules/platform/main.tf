# Cluster add-ons and the gateway release.
#
# This module is where the multi-cloud claim is actually tested. It takes only
# the contract outputs from ../CONTRACT.md and never learns which cloud it is
# on — the single exception is the ClusterSecretStore below, where the provider
# block genuinely differs, and even that is a lookup on `secret_store_backend`
# rather than a chain of conditionals.
#
# If you find yourself adding `if var.cloud == "aws"` here, the contract has
# sprung a leak and the fix belongs in the cloud module, not here.

terraform {
  required_version = ">= 1.9"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
  }
}

locals {
  # Namespaces this module owns. Created here rather than by each chart's
  # `createNamespace`, so deletion ordering is explicit and a destroy does not
  # strand a namespace in Terminating.
  namespaces = toset([
    var.external_secrets_namespace,
    var.ingress_namespace,
    var.monitoring_namespace,
    var.gateway_namespace,
  ])
}

resource "kubernetes_namespace" "this" {
  for_each = local.namespaces

  metadata {
    name = each.value
    labels = {
      # The chart's NetworkPolicy selects peers by this label. Most
      # distributions set it automatically, but not all, and a missing label
      # means the policy matches nothing and silently blocks all ingress.
      "kubernetes.io/metadata.name" = each.value
      "app.kubernetes.io/part-of"   = "skyl"
    }
  }
}

# --- External Secrets Operator -----------------------------------------------

resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = var.external_secrets_version
  namespace  = kubernetes_namespace.this[var.external_secrets_namespace].metadata[0].name

  # The CRDs must exist before the ClusterSecretStore and the chart's
  # ExternalSecret are applied. Without this the first apply fails on an
  # unknown kind and the second succeeds, which makes the failure look
  # intermittent.
  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = var.external_secrets_sa_name
  }

  # The workload identity annotation, straight from the cloud module. The key
  # differs per cloud; this module never reads it.
  dynamic "set" {
    for_each = var.workload_identity_annotation
    content {
      name  = "serviceAccount.annotations.${replace(set.key, ".", "\\.")}"
      value = set.value
    }
  }

  # Azure workload identity needs this label on the pod or the webhook does not
  # inject the token. It is inert on AWS and GCP, so it is set unconditionally
  # rather than behind a provider check.
  set {
    name  = "podLabels.azure\\.workload\\.identity/use"
    value = "true"
  }

  wait    = true
  timeout = 600
}

# The one place a provider difference is unavoidable: each backend takes a
# different provider block. Expressed as a single templated document keyed by
# `secret_store_backend` rather than three resources with count guards.
resource "kubectl_manifest" "cluster_secret_store" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = var.secret_store_name
    }
    spec = {
      provider = {
        (var.secret_store_backend) = merge(
          var.secret_store_config,
          # Each backend names its workload-identity auth differently. This is
          # the whole provider-specific surface of the platform layer.
          {
            aws = {
              auth = {
                jwt = {
                  serviceAccountRef = {
                    name      = var.external_secrets_sa_name
                    namespace = var.external_secrets_namespace
                  }
                }
              }
            }
            gcpsm = {
              auth = {
                workloadIdentity = {
                  clusterLocation = var.region
                  clusterName     = var.cluster_name
                  serviceAccountRef = {
                    name      = var.external_secrets_sa_name
                    namespace = var.external_secrets_namespace
                  }
                }
              }
            }
            azurekv = {
              authType = "WorkloadIdentity"
              serviceAccountRef = {
                name      = var.external_secrets_sa_name
                namespace = var.external_secrets_namespace
              }
            }
          }[var.secret_store_backend]
        )
      }
    }
  })

  depends_on = [helm_release.external_secrets]
}

# --- ingress -----------------------------------------------------------------

resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = var.ingress_nginx_version
  namespace  = kubernetes_namespace.this[var.ingress_namespace].metadata[0].name

  values = [yamlencode({
    controller = {
      replicaCount = var.environment == "prod" ? 2 : 1

      # Local, not Cluster. Preserves the client source IP, which the gateway
      # logs and which any future rate limiting depends on. The trade is that
      # traffic only reaches nodes running a controller pod — fine, since the
      # cloud load balancer health-checks them.
      service = {
        externalTrafficPolicy = "Local"
      }

      config = {
        # SSE again, at the controller default level. The per-Ingress
        # annotations in the chart cover skyl; this covers anything else
        # deployed alongside it.
        "proxy-read-timeout"    = "600"
        "proxy-send-timeout"    = "600"
        "use-forwarded-headers" = "true"
        # Logs as JSON so they parse the same way as the gateway's own output.
        "log-format-escape-json" = "true"
      }

      metrics = {
        enabled = true
        serviceMonitor = {
          enabled   = var.monitoring_enabled
          namespace = var.monitoring_namespace
        }
      }

      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { memory = "512Mi" }
      }
    }
  })]

  wait    = true
  timeout = 600

  depends_on = [kubernetes_namespace.this]
}

resource "helm_release" "cert_manager" {
  count = var.cert_manager_enabled ? 1 : 0

  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = var.cert_manager_version
  namespace  = kubernetes_namespace.this[var.ingress_namespace].metadata[0].name

  set {
    name  = "crds.enabled"
    value = "true"
  }

  wait    = true
  timeout = 600
}

# --- observability -----------------------------------------------------------

resource "helm_release" "kube_prometheus_stack" {
  count = var.monitoring_enabled ? 1 : 0

  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.kube_prometheus_stack_version
  namespace  = kubernetes_namespace.this[var.monitoring_namespace].metadata[0].name

  values = [yamlencode({
    prometheus = {
      prometheusSpec = {
        retention = var.environment == "prod" ? "30d" : "7d"

        # Empty selectors mean "watch every namespace". The default is to match
        # only resources carrying the release label, which silently ignores the
        # gateway's ServiceMonitor and PrometheusRule — a scrape that never
        # happens and an alert that never fires, with nothing in any log.
        serviceMonitorSelectorNilUsesHelmValues = false
        ruleSelectorNilUsesHelmValues           = false
        podMonitorSelectorNilUsesHelmValues     = false

        resources = {
          requests = { cpu = "200m", memory = "1Gi" }
          limits   = { memory = "2Gi" }
        }
      }
    }
    grafana = {
      enabled = var.grafana_enabled
      # No default admin password here: it would live in Terraform state. The
      # chart generates one; read it from the secret it creates.
      defaultDashboardsTimezone = "utc"
    }
    # The gateway is the workload of interest; node and etcd dashboards come
    # from the cloud's own managed monitoring.
    kubeEtcd              = { enabled = false }
    kubeControllerManager = { enabled = false }
    kubeScheduler         = { enabled = false }
  })]

  wait    = true
  timeout = 900

  depends_on = [kubernetes_namespace.this]
}

# --- the gateway -------------------------------------------------------------

resource "helm_release" "skyl_gateway" {
  name      = "skyl-gateway"
  chart     = "${path.module}/../../../charts/skyl-gateway"
  namespace = kubernetes_namespace.this[var.gateway_namespace].metadata[0].name

  values = [yamlencode(merge({
    image = {
      digest = var.gateway_image_digest
    }
    ingress = {
      enabled   = length(var.gateway_hosts) > 0
      className = var.ingress_class
      hosts = [for h in var.gateway_hosts : {
        host  = h
        paths = [{ path = "/", pathType = "Prefix" }]
      }]
      tls = var.cert_manager_enabled && length(var.gateway_hosts) > 0 ? [{
        secretName = "skyl-gateway-tls"
        hosts      = var.gateway_hosts
      }] : []
      annotations = var.cert_manager_enabled ? {
        "cert-manager.io/cluster-issuer" = var.cluster_issuer_name
      } : {}
    }
    secrets = {
      externalSecrets = {
        enabled = true
        secretStoreRef = {
          name = var.secret_store_name
          kind = "ClusterSecretStore"
        }
      }
    }
    serviceMonitor = { enabled = var.monitoring_enabled }
    prometheusRule = { enabled = var.monitoring_enabled }
    networkPolicy = {
      enabled = true
      ingressNamespaceSelector = {
        "kubernetes.io/metadata.name" = var.ingress_namespace
      }
      metricsNamespaceSelector = {
        "kubernetes.io/metadata.name" = var.monitoring_namespace
      }
    }
    # The image is multi-arch, so this is a scheduling hint rather than a
    # requirement — it keeps pods on the cheaper node pool where one exists.
    nodeSelector = {
      "kubernetes.io/arch" = var.node_architecture
    }
  }, var.gateway_values))]

  wait    = true
  timeout = 600

  depends_on = [
    kubectl_manifest.cluster_secret_store,
    helm_release.ingress_nginx,
  ]
}
