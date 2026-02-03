# S3 bucket for RAG documents
resource "aws_s3_bucket" "rag_documents" {
  bucket = "faro-rag-documents-${data.aws_region.current.name}"

  tags = {
    Name        = "RAG Documents"
    Environment = "production"
    Project     = "kubernetes-rag"
  }
}

# Enable versioning (protect against accidental deletes)
resource "aws_s3_bucket_versioning" "rag_documents" {
  bucket = aws_s3_bucket.rag_documents.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "rag_documents" {
  bucket = aws_s3_bucket.rag_documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access (security!)
resource "aws_s3_bucket_public_access_block" "rag_documents" {
  bucket = aws_s3_bucket.rag_documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy (optional - clean up old processed files after 90 days)
resource "aws_s3_bucket_lifecycle_configuration" "rag_documents" {
  bucket = aws_s3_bucket.rag_documents.id

  rule {
    id     = "clean-processed"
    status = "Enabled"

    filter {
      prefix = "processed/"
    }

    expiration {
      days = 90
    }
  }
}

# IAM policy for Kubernetes pods to access S3
resource "aws_iam_policy" "s3_rag_access" {
  name        = "s3-rag-access"
  description = "Allow RAG services to read/write S3 documents"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.rag_documents.arn,
          "${aws_s3_bucket.rag_documents.arn}/*"
        ]
      }
    ]
  })
}

# Output for your pods to use
output "s3_bucket_name" {
  value = aws_s3_bucket.rag_documents.id
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.rag_documents.arn
}