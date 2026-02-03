#####################################
# ECR Repository: Embeddings Engine Service
# Generates vector embeddings using AWS Bedrock API
#####################################

resource "aws_ecr_repository" "embeddings_engine" {
  name                 = "faro-rag/embeddings-engine"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = "Embeddings Engine Service"
    Project     = "Faro RAG Pipeline"
    Environment = "production"
    Service     = "embeddings"
  }
}

resource "aws_ecr_lifecycle_policy" "embeddings_engine_policy" {
  repository = aws_ecr_repository.embeddings_engine.name

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

output "ecr_embeddings_engine_url" {
  description = "ECR Repository URL for Embeddings Engine Service"
  value       = aws_ecr_repository.embeddings_engine.repository_url
}
