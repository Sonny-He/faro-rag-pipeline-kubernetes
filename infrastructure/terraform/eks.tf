# IAM Role for EKS Cluster Control Plane
resource "aws_iam_role" "eks_cluster" {
  name = "faro-rag-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# The EKS Cluster Resource
resource "aws_eks_cluster" "main" {
  name     = "faro-rag-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.34"

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    # DEV SYNTAX: accessing subnets via map keys
    subnet_ids = [
      aws_subnet.private["service_subnet"].id,
      aws_subnet.private["db_private"].id
    ]
    security_group_ids = [aws_security_group.kuber.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}

# IAM Role for Worker Nodes
resource "aws_iam_role" "eks_nodes" {
  name = "faro-rag-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

# The Node Group (Actual Servers)
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "faro-rag-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn

  # DEV SYNTAX: accessing subnets via map keys
  subnet_ids = [aws_subnet.private["service_subnet"].id, aws_subnet.private["db_private"].id]

  scaling_config {
    desired_size = 3
    max_size     = 4
    min_size     = 1
  }

  instance_types = ["t3.medium"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_registry_policy,
  ]
}

# Allow EKS nodes to talk to S3
resource "aws_iam_role_policy_attachment" "nodes_s3_access" {
  policy_arn = aws_iam_policy.s3_rag_access.arn
  role       = aws_iam_role.eks_nodes.name
}

# OIDC Provider for EKS (needed for IRSA - IAM Roles for Service Accounts)
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = {
    Name = "faro-rag-cluster-oidc"
  }
}

# IAM Role for RAG Service Pods (IRSA)
resource "aws_iam_role" "rag_services" {
  name = "rag-services-s3-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Condition = {
        StringEquals = {
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" = "system:serviceaccount:rag-services:rag-services-sa"
          "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Name = "RAG Services S3 Access"
  }
}

# Attach S3 policy to RAG services role
resource "aws_iam_role_policy_attachment" "rag_services_s3" {
  policy_arn = aws_iam_policy.s3_rag_access.arn
  role       = aws_iam_role.rag_services.name
}

# Add "Sonny" as a user allowed to access the cluster
resource "aws_eks_access_entry" "admin_sonny" {
  cluster_name = aws_eks_cluster.main.name
  # This matches the ARN from your 'aws sts get-caller-identity' output
  principal_arn = "arn:aws:iam::894866952568:user/Sonny"
  type          = "STANDARD"
}

# Grant "Sonny" full Cluster Admin permissions
resource "aws_eks_access_policy_association" "admin_sonny_policy" {
  cluster_name  = aws_eks_cluster.main.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = aws_eks_access_entry.admin_sonny.principal_arn

  access_scope {
    type = "cluster"
  }
}