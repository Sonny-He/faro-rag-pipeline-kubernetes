resource "kubernetes_config_map" "rag_dashboard" {
  metadata {
    name      = "rag-performance-dashboard"
    namespace = "monitoring"
    labels = {
      grafana_dashboard = "1" # This label tells Grafana "Import me!"
    }
  }

  depends_on = [helm_release.kube_prometheus_stack]

  data = {
    "rag-dashboard.json" = <<EOF
{
  "title": "FARO RAG Pipeline Performance",
  "panels": [
    {
      "title": "Total Vectors (Postgres)",
      "type": "stat",
      "targets": [
        { "expr": "pg_stat_user_tables_n_live_tup{relname='embeddings'}" }
      ],
      "gridPos": { "h": 4, "w": 6, "x": 0, "y": 0 },
      "description": "Total rows in the 'embeddings' table"
    },
    {
      "title": "Total Vectors (Qdrant)",
      "type": "stat",
      "targets": [
        { "expr": "collection_vectors{collection='faro_docs'}" }
      ],
      "gridPos": { "h": 4, "w": 6, "x": 6, "y": 0 },
      "description": "Total vectors in 'faro_docs' collection"
    },
    {
      "title": "Vector Search Latency (Comparison)",
      "type": "timeseries",
      "targets": [
        {
          "legendFormat": "Qdrant",
          "expr": "rate(rag_search_latency_seconds_sum{database='qdrant'}[1m]) / rate(rag_search_latency_seconds_count{database='qdrant'}[1m])"
        },
        {
          "legendFormat": "Postgres",
          "expr": "rate(rag_search_latency_seconds_sum{database='postgres'}[1m]) / rate(rag_search_latency_seconds_count{database='postgres'}[1m])"
        }
      ],
      "gridPos": { "h": 8, "w": 12, "x": 0, "y": 4 },
      "unit": "s",
      "description": "Average search duration per database"
    },
    {
      "title": "Result Overlap (Accuracy Proxy)",
      "type": "gauge",
      "targets": [
        {
          "expr": "avg_over_time(rag_search_overlap_ratio[1m]) * 100"
        }
      ],
      "gridPos": { "h": 6, "w": 6, "x": 12, "y": 4 },
      "min": 0,
      "max": 100,
      "thresholds": {
        "steps": [
          { "color": "red", "value": 0 },
          { "color": "yellow", "value": 50 },
          { "color": "green", "value": 80 }
        ]
      },
      "unit": "percent",
      "description": "Percentage of top-k results shared between Qdrant and Postgres"
    },
    {
      "title": "Postgres Active Connections",
      "type": "timeseries",
      "targets": [
        { "expr": "pg_stat_activity_count" }
      ],
      "gridPos": { "h": 6, "w": 6, "x": 0, "y": 12 }
    }
  ]
}
EOF
  }
}