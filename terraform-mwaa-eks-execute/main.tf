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

resource "random_id" "unique_suffix" {
  byte_length = 4
}

resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "vpc-${local.name_suffix}"
  })
}

resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.${count.index}.0/24"
  availability_zone = "us-east-1${count.index == 0 ? "a" : "b"}"

  tags = merge(local.common_tags, {
    Name = "subnet-public-${count.index}-${local.name_suffix}"
  })
}

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

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = merge(local.common_tags, {
    Name = "igw-${local.name_suffix}"
  })
}

resource "aws_eip" "nat" {
  count  = 2
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "eip-nat-${count.index}-${local.name_suffix}"
  })
}

resource "aws_nat_gateway" "nat" {
  count         = 2
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(local.common_tags, {
    Name = "nat-${count.index}-${local.name_suffix}"
  })
}

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
  bucket        = "mwaa-bucket-${local.name_suffix}-${random_id.unique_suffix.hex}"
  force_destroy = true

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

resource "aws_s3_object" "dags_folder" {
  bucket  = aws_s3_bucket.mwaa.id
  key     = "dags/"
  content = ""
}

resource "aws_s3_object" "mwaa_requirements" {
  bucket = aws_s3_bucket.mwaa.id
  key    = "requirements.txt"
  source = "${path.module}/files/requirements.txt"
  etag   = filemd5("${path.module}/files/requirements.txt")
}


# IAM Role and Policy for MWAA
resource "aws_iam_role" "mwaa_service_role" {
  name = "mwaa-service-role-${local.name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "airflow-env.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_policy" "mwaa_execution_policy" {
  name = "mwaa-execution-policy-${local.name_suffix}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
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
        ],
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
  environment_class  = "mw1.small"
  webserver_access_mode = "PUBLIC_ONLY"
  max_workers        = 1
  min_workers        = 1

  requirements_s3_path = "requirements.txt"
  
  network_configuration {
    security_group_ids = [aws_security_group.mwaa.id]
    subnet_ids         = aws_subnet.private[*].id
  }

  logging_configuration {
    dag_processing_logs {
      enabled   = true
      log_level = "INFO"
    }
    scheduler_logs {
      enabled   = true
      log_level = "INFO"
    }
    task_logs {
      enabled   = true
      log_level = "INFO"
    }
    webserver_logs {
      enabled   = true
      log_level = "INFO"
    }
    worker_logs {
      enabled   = true
      log_level = "INFO"
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_s3_object.dags_folder
  ]
}


# IAM role for EKS cluster
resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster-role-${local.name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role" "mwaa_to_eks" {
  name = "mwaa-to-eks-role-${local.name_suffix}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "airflow.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
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
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
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

#ECR
resource "aws_ecr_repository" "airflow_task_repo" {
  name = "airflow-mwaa-ecr"

  image_tag_mutability = "MUTABLE"
  force_delete          = true

  tags = merge(local.common_tags, {
    Name = "airflow-mwaa-ecr"
  })
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


data "aws_eks_cluster" "eks_data" {
  name = aws_eks_cluster.eks.name
}

data "aws_eks_cluster_auth" "eks_auth" {
  name = aws_eks_cluster.eks.name
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da0afd40f94"]
  url             = data.aws_eks_cluster.eks_data.identity[0].oidc[0].issuer
}

resource "aws_iam_role" "airflow_eks_irsa" {
  name = "airflow-eks-irsa-${local.name_suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      },
      Action = "sts:AssumeRoleWithWebIdentity",
      Condition = {
        StringEquals = {
          "${replace(data.aws_eks_cluster.eks_data.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:airflow:airflow-irsa"
        }
      }
    }]
  })

  tags = local.common_tags
}


resource "aws_iam_role_policy_attachment" "airflow_eks_irsa_policy" {
  role       = aws_iam_role.airflow_eks_irsa.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks_data.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks_data.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks_auth.token
}

resource "kubernetes_namespace" "airflow" {
  metadata {
    name = "airflow"
  }
}

resource "kubernetes_service_account" "airflow_irsa" {
  metadata {
    name      = "airflow-irsa"
    namespace = kubernetes_namespace.airflow.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.airflow_eks_irsa.arn
    }
  }
}