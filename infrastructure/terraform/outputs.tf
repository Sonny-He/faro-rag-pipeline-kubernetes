output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = { for k, s in aws_subnet.public : k => s.id }
}

output "private_subnet_ids" {
  value = { for k, s in aws_subnet.private : k => s.id }
}

output "nat_gateway_id" {
  value = aws_nat_gateway.nat.id
}

output "public_route_table_id" {
  value = aws_route_table.public.id
}

output "private_route_table_id" {
  value = aws_route_table.private.id
}

output "s3_vpc_endpoint_id" {
  value = aws_vpc_endpoint.s3.id
}

# Qdrant Info
output "qdrant_private_ip" {
  value       = "10.0.11.10"
  description = "Private IP of Qdrant instance"
}

output "qdrant_endpoint" {
  value       = "http://10.0.11.10:6333"
  description = "Qdrant REST API endpoint"
}

# RDS Info
output "rds_endpoint" {
  value       = aws_db_instance.vector_db.endpoint
  description = "RDS PostgreSQL endpoint"
}

output "rds_port" {
  value       = aws_db_instance.vector_db.port
  description = "RDS PostgreSQL port"
}

# EKS Cluster outputs
output "cluster_name" {
  value = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority" {
  value = aws_eks_cluster.main.certificate_authority[0].data
}

# IAM Role ARN for Kubernetes Service Account
output "rag_services_role_arn" {
  description = "IAM role ARN for RAG services (use in k8s service account)"
  value       = aws_iam_role.rag_services.arn
}

output "grafana_internal_url" {
  description = "Internal URL for Grafana (Access via VPN)"
  value       = "http://${data.kubernetes_service.grafana.status.0.load_balancer.0.ingress.0.hostname}"
}