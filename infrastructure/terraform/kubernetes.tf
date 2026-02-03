# 1. Create the namespace first
resource "kubernetes_namespace" "rag_services" {
  metadata {
    name = "rag-services"
  }
}

# 2. Create the secret inside that namespace
resource "kubernetes_secret" "rag_secrets" {
  metadata {
    name      = "rag-secrets"
    namespace = kubernetes_namespace.rag_services.metadata[0].name
  }

  data = {
    # Keys must match what k8s/embeddings.yaml expects
    "db-password"     = var.db_password
    "portkey-api-key" = var.portkey_api_key
    "openai-api-key"  = var.openai_api_key
  }

  type = "Opaque"
}
