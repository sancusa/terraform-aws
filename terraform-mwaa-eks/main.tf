provider "aws" {
  region = "us-east-1"
}

locals {
  name_suffix = "terraform-mwaa-amazonq"
  common_tags = {
    App          = "terraform-mwaa-amazonq"
    CreationTime = timestamp()
  }
}

# VPC and Network Resources
resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = merge(local.common_tags, {
    Name = "vpc-${local.name_suffix}"
  })
}

# Public subnets for NAT gateways
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.${count.index}.0/24"
  availability_zone = "us-east-1${count.index == 0 ? "a" : "b"}"
  
  tags = merge(local.common_tags, {
    Name = "subnet-public-${count.index}-${local.name_suffix}"
  })
}

# Private subnets for MWAA and EKS
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = "us-east-1${count.index == 0 ? "a" : "b"}"
  
  tags = merge(local.common_tags, {
    Name = "subnet-private-${count.index}-${local.name_suffix}"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  
  tags = merge(local.common_tags, {
    Name = "igw-${local.name_suffix}"
  })
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count  = 2
  domain = "vpc"
  
  tags = merge(local.common_tags, {
    Name = "eip-nat-${count.index}-${local.name_suffix}"
  })
}

# NAT Gateways
resource "aws_nat_gateway" "nat" {
  count         = 2
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  
  tags = merge(local.common_tags, {
    Name = "nat-${count.index}-${local.name_suffix}"
  })
}

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  
  tags = merge(local.common_tags, {
    Name = "rt-public-${local.name_suffix}"
  })
}

resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.vpc.id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat[count.index].id
  }
  
  tags = merge(local.common_tags, {
    Name = "rt-private-${count.index}-${local.name_suffix}"
  })
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Security Group for MWAA
resource "aws_security_group" "mwaa" {
  name        = "mwaa-sg-${local.name_suffix}"
  description = "Security group for MWAA environment"
  vpc_id      = aws_vpc.vpc.id
  
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "Allow all traffic within the security group"
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }
  
  tags = merge(local.common_tags, {
    Name = "mwaa-sg-${local.name_suffix}"
  })
}

# S3 bucket for MWAA
resource "aws_s3_bucket" "mwaa" {
  bucket = "mwaa-bucket-${local.name_suffix}"
  
  tags = merge(local.common_tags, {
    Name = "s3-mwaa-${local.name_suffix}"
  })
}

resource "aws_s3_bucket_versioning" "mwaa" {
  bucket = aws_s3_bucket.mwaa.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "mwaa" {
  bucket                  = aws_s3_bucket.mwaa.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Create DAGs folder in S3
resource "aws_s3_object" "dags_folder" {
  bucket  = aws_s3_bucket.mwaa.id
  key     = "dags/"
  content = ""
}

# Fix the IAM role for MWAA
resource "aws_iam_role" "mwaa_service_role" {
  name = "mwaa-service-role-${local.name_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "airflow-env.amazonaws.com"  # Changed from airflow.amazonaws.com
        }
      }
    ]
  })
  
  tags = local.common_tags
}

# Create MWAA execution policy
resource "aws_iam_policy" "mwaa_execution_policy" {
  name = "mwaa-execution-policy-${local.name_suffix}"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "airflow:*",
          "s3:*",
          "logs:*",
          "cloudwatch:*",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:DescribeNetworkInterfaces",
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:GenerateDataKey*",
          "kms:Encrypt",
          "sqs:ChangeMessageVisibility",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage",
          "sqs:SendMessage",
          "iam:PassRole"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "mwaa_policy" {
  role       = aws_iam_role.mwaa_service_role.name
  policy_arn = aws_iam_policy.mwaa_execution_policy.arn
}

# MWAA Environment
resource "aws_mwaa_environment" "mwaa" {
  name               = "mwaa-env-${local.name_suffix}"
  execution_role_arn = aws_iam_role.mwaa_service_role.arn
  source_bucket_arn  = aws_s3_bucket.mwaa.arn
  
  dag_s3_path        = "dags/"
  
  # Cost optimized - smallest environment class
  environment_class  = "mw1.small"
  
  # Minimum settings
  max_workers        = 1
  min_workers        = 1
  
  network_configuration {
    security_group_ids = [aws_security_group.mwaa.id]
    subnet_ids         = aws_subnet.private[*].id
  }
  
  logging_configuration {
    dag_processing_logs {
      enabled   = true
      log_level = "WARNING"
    }
    
    scheduler_logs {
      enabled   = true
      log_level = "WARNING"
    }
    
    task_logs {
      enabled   = true
      log_level = "WARNING"
    }
    
    webserver_logs {
      enabled   = true
      log_level = "WARNING"
    }
    
    worker_logs {
      enabled   = true
      log_level = "WARNING"
    }
  }
  
  tags = local.common_tags
  
  depends_on = [
    aws_s3_object.dags_folder
  ]
}

# IAM role for EKS
resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster-role-${local.name_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# IAM role for Fargate pods
resource "aws_iam_role" "fargate_pod_execution" {
  name = "eks-fargate-pod-execution-role-${local.name_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks-fargate-pods.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "fargate_pod_execution" {
  role       = aws_iam_role.fargate_pod_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

# EKS Cluster
resource "aws_eks_cluster" "eks" {
  name     = "eks-cluster-${local.name_suffix}"
  role_arn = aws_iam_role.eks_cluster.arn
  
  vpc_config {
    subnet_ids = aws_subnet.private[*].id
  }
  
  tags = local.common_tags
  
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}

# EKS Fargate Profile
resource "aws_eks_fargate_profile" "main" {
  cluster_name           = aws_eks_cluster.eks.name
  fargate_profile_name   = "fp-default-${local.name_suffix}"
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution.arn
  subnet_ids             = aws_subnet.private[*].id
  
  selector {
    namespace = "default"
  }
  
  selector {
    namespace = "kube-system"
  }
  
  tags = local.common_tags
}


# Outputs
output "mwaa_webserver_url" {
  value = aws_mwaa_environment.mwaa.webserver_url
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.eks.endpoint
}

output "eks_cluster_name" {
  value = aws_eks_cluster.eks.name
}