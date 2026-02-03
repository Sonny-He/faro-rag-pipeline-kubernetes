resource "aws_security_group" "vpn" {
  name        = "vpn"
  description = "Admin VPN or bastion entry point"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from admin networks"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "OpenVPN UDP"
    from_port   = 1194
    to_port     = 1194
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound to anywhere (to reach like nodes, DB)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Kubernetes nodes security group
resource "aws_security_group" "kuber" {
  name        = "kuber"
  description = "Kubernetes worker/master nodes"
  vpc_id      = aws_vpc.main.id

  # SSH from vpn SG
  ingress {
    description     = "SSH from vpn"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.vpn.id]
  }

  # Node-to-node traffic inside the cluster
  ingress {
    description = "Node-to-node traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Traffic from the public load balancer to NodePorts on the nodes
  ingress {
    description     = "Traffic from ingress load balancer to NodePorts"
    from_port       = 30000
    to_port         = 32767
    protocol        = "tcp"
    security_groups = [aws_security_group.ingress_lb.id]
  }

  # Outbound allow nodes to reach internet via NAT, S3, RDS.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Public load balancer in front of NGINX Ingress
resource "aws_security_group" "ingress_lb" {
  name        = "ingress_lb"
  description = "Public load balancer for ingress into the cluster"
  vpc_id      = aws_vpc.main.id

  # Internet users hitting HTTP
  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Internet users hitting HTTPS
  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound: to cluster nodes (targets). We keep this open; the
  # actual target restriction is done via the LB target group.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# RDS pgvector database security group
resource "aws_security_group" "rds_vector" {
  name        = "rds_vector"
  description = "RDS pgvector database access"
  vpc_id      = aws_vpc.main.id

  # Postgres from Kubernetes nodes
  ingress {
    description     = "Postgres from Kubernetes nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
  }

  # Postgres from VPN/bastion for admin access (psql, migrations)
  ingress {
    description     = "Postgres from vpn/bastion"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.vpn.id]
  }

  # Outbound: allow DB to respond and reach AWS services as needed
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Monitoring SG (Prometheus + Grafana style)
resource "aws_security_group" "monitoring" {
  name        = "monitoring"
  description = "Monitoring and dashboard access (Prometheus, Grafana)"
  vpc_id      = aws_vpc.main.id

  # Grafana UI from VPN/bastion
  ingress {
    description     = "Grafana UI from vpn"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.vpn.id]
  }

  # Prometheus UI or HTTP access from VPN/bastion (optional)
  ingress {
    description     = "Prometheus/HTTP from vpn"
    from_port       = 9090
    to_port         = 9090
    protocol        = "tcp"
    security_groups = [aws_security_group.vpn.id]
  }

  # Outbound: scrape nodes, talk to alerting, etc.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Future: CloudWatch / managed Grafana option
resource "aws_security_group" "cloudwatch_grafana" {
  name        = "cloudwatsch_grafana"
  description = "For CloudWatch agent / managed Grafana access"
  vpc_id      = aws_vpc.main.id

  # Access to Grafana UI or any EC2 running CloudWatch/Grafana components
  ingress {
    description     = "Grafana/CloudWatch UI from vpn"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.vpn.id]
  }

  # Optional: HTTPS UI (if you front it with 443)
  ingress {
    description     = "HTTPS UI from vpn"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.vpn.id]
  }

  # Outbound: send metrics/logs to CloudWatch and talk to cluster/DB if needed
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security group for Qdrant
resource "aws_security_group" "qdrant" {
  name        = "qdrant"
  description = "Qdrant vector database access"
  vpc_id      = aws_vpc.main.id

  # Qdrant REST API from Kubernetes nodes
  ingress {
    description     = "Qdrant REST API from K8s"
    from_port       = 6333
    to_port         = 6333
    protocol        = "tcp"
    security_groups = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
  }

  # Qdrant gRPC API from Kubernetes nodes (optional, for better performance)
  ingress {
    description     = "Qdrant gRPC from K8s"
    from_port       = 6334
    to_port         = 6334
    protocol        = "tcp"
    security_groups = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
  }

  # SSH from VPN for admin access
  ingress {
    description     = "SSH from vpn"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.vpn.id]
  }

  # Qdrant API from VPN for testing
  ingress {
    description     = "Qdrant API from vpn"
    from_port       = 6333
    to_port         = 6333
    protocol        = "tcp"
    security_groups = [aws_security_group.vpn.id]
  }

  ingress {
    description     = "Qdrant REST API from Worker Nodes"
    from_port       = 6333
    to_port         = 6333
    protocol        = "tcp"
    security_groups = [aws_security_group.kuber.id]
  }
  
  # Outbound to internet for Docker pulls
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "qdrant-sg"
  }
}