# ---------------------------------------------------------
# 1. QDRANT BRIDGE (EC2 -> K8s)
# ---------------------------------------------------------
# Define a Service without a selector (Headless-ish)
resource "kubernetes_service" "qdrant_external" {
  metadata {
    name      = "qdrant-external"
    namespace = "rag-services"
    labels = {
      app = "qdrant-db"
    }
  }
  spec {
    port {
      name        = "http-metrics"
      port        = 6333
      target_port = 6333
    }
  }
}

# Manually map the Service to the EC2 IP
resource "kubernetes_endpoints" "qdrant_external" {
  metadata {
    name      = "qdrant-external"
    namespace = "rag-services"
  }
  subset {
    address {
      ip = "10.0.11.10" # Static IP from qdrant.tf
    }
    port {
      name     = "http-metrics"
      port     = 6333
    }
  }
}

# ---------------------------------------------------------
# 2. SERVICEMONITORS (Prometheus Configuration)
# ---------------------------------------------------------

# Scrape Qdrant (via the bridge above)
resource "kubernetes_manifest" "qdrant_monitor" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "qdrant-monitor"
      namespace = "monitoring"
      labels = {
        release = "prometheus" 
      }
    }
    spec = {
      selector = {
        matchLabels = {
          app = "qdrant-db"
        }
      }
      namespaceSelector = {
        matchNames = ["rag-services"]
      }
      endpoints = [
        {
          port     = "http-metrics"
          path     = "/metrics"
          interval = "15s"
        }
      ]
    }
  }
  depends_on = [helm_release.kube_prometheus_stack]
}

# Scrape RAG Query Service (Pods)
resource "kubernetes_manifest" "rag_query_monitor" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "rag-query-monitor"
      namespace = "monitoring"
      labels = {
        release = "prometheus"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          app = "rag-query" 
        }
      }
      namespaceSelector = {
        matchNames = ["rag-services"]
      }
      endpoints = [
        {
          port     = "http" 
          path     = "/metrics"
          interval = "15s"
        }
      ]
    }
  }
  depends_on = [helm_release.kube_prometheus_stack]
}