#####################################
# ECR Repository: RAG Query Service
# Retrieves relevant chunks and generates responses
#####################################

resource "aws_ecr_repository" "rag_query" {
  name                 = "faro-rag/rag-query"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = "RAG Query Service"
    Project     = "Faro RAG Pipeline"
    Environment = "production"
    Service     = "query"
  }
}

resource "aws_ecr_lifecycle_policy" "rag_query_policy" {
  repository = aws_ecr_repository.rag_query.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only the last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

output "ecr_rag_query_url" {
  description = "ECR Repository URL for RAG Query Service"
  value       = aws_ecr_repository.rag_query.repository_url
}
