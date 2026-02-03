#####################################
# ECR Repository: Document Chunking Service
# Splits PDF/DOCX/TXT files into semantic text chunks
#####################################

resource "aws_ecr_repository" "document_chunking" {
  name                 = "faro-rag/document-chunking"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = "Document Chunking Service"
    Project     = "Faro RAG Pipeline"
    Environment = "production"
    Service     = "chunking"
  }
}

resource "aws_ecr_lifecycle_policy" "document_chunking_policy" {
  repository = aws_ecr_repository.document_chunking.name

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

output "ecr_document_chunking_url" {
  description = "ECR Repository URL for Document Chunking Service"
  value       = aws_ecr_repository.document_chunking.repository_url
}
