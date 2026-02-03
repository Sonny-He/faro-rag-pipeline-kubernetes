# RDS subnet group (spans both private subnets for HA)
resource "aws_db_subnet_group" "vector_db" {
  name = "vector-db-subnet-group"
  subnet_ids = [
    aws_subnet.private["service_subnet"].id,
    aws_subnet.private["db_private"].id
  ]

  tags = {
    Name = "Vector DB Subnet Group"
  }
}

# RDS PostgreSQL instance with pgvector
resource "aws_db_instance" "vector_db" {
  identifier = "rag-vector-db"

  # Database config
  engine            = "postgres"
  engine_version    = "15.15"       # pgvector supported from 15+
  instance_class    = "db.t3.micro" # Free tier eligible
  allocated_storage = 20
  storage_type      = "gp2"
  storage_encrypted = true

  # Database credentials
  db_name  = "vectordb"
  username = var.db_username
  password = var.db_password

  # Network
  db_subnet_group_name   = aws_db_subnet_group.vector_db.name
  vpc_security_group_ids = [aws_security_group.rds_vector.id]
  publicly_accessible    = false

  # Backup config
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "mon:04:00-mon:05:00"

  # Performance
  multi_az = false # Set to true for production HA

  # Deletion protection (set to true in production!)
  skip_final_snapshot = true
  deletion_protection = false

  # Enable auto minor version upgrades
  auto_minor_version_upgrade = true

  tags = {
    Name = "RAG Vector Database"
  }
}
