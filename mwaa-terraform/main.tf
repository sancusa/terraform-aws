provider "aws" {
  region = "us-east-1"
}

# -------------------------------
# 1. VPC & Networking Resources
# -------------------------------
resource "aws_vpc" "mwaa_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "mwaa-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.mwaa_vpc.id
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.mwaa_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.mwaa_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = { Name = "public-a" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.mwaa_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = { Name = "public-b" }
}

resource "aws_route_table_association" "pub_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "pub_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_eip" "nat_eip" {}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_a.id
}

resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.mwaa_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.mwaa_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "private-a" }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.mwaa_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "private-b" }
}

resource "aws_route_table_association" "priv_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_route_table_association" "priv_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private_rt.id
}

resource "aws_security_group" "mwaa_sg" {
  name   = "mwaa-sg"
  vpc_id = aws_vpc.mwaa_vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "mwaa-sg" }
}

# -------------------------------
# 2. S3 Bucket for DAGs
# -------------------------------
resource "aws_s3_bucket" "mwaa_dags" {
  bucket        = "my-mwaa-dags-bucket-unique-123456"
  force_destroy = true
  tags = { Name = "mwaa-dags" }
}

# -------------------------------
# 3. IAM Role & Inline Policy
# -------------------------------
resource "aws_iam_role" "mwaa_execution_role" {
  name = "mwaa-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "airflow-env.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "mwaa_inline_policy" {
  name = "mwaa-inline-policy"
  role = aws_iam_role.mwaa_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ],
        Resource = [
          aws_s3_bucket.mwaa_dags.arn,
          "${aws_s3_bucket.mwaa_dags.arn}/*"
        ]
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "s3:GetAccountPublicAccessBlock",
          "s3:GetBucketPublicAccessBlock"
        ],
        Resource = [
          "*",
          aws_s3_bucket.mwaa_dags.arn
        ]
      }
    ]
  })
}

# -------------------------------
# 4. MWAA Environment
# -------------------------------
resource "aws_mwaa_environment" "mwaa" {
  name                    = "example-mwaa"
  airflow_version         = "2.7.2"
  environment_class       = "mw1.small"
  execution_role_arn      = aws_iam_role.mwaa_execution_role.arn
  source_bucket_arn       = aws_s3_bucket.mwaa_dags.arn
  dag_s3_path             = "dags"
  webserver_access_mode   = "PUBLIC_ONLY"
  max_workers             = 5
  min_workers             = 1
  schedulers              = 2

  network_configuration {
    security_group_ids = [aws_security_group.mwaa_sg.id]
    subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
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

  airflow_configuration_options = {
    "core.default_timezone" = "utc"
  }

  tags = {
    Name = "example-mwaa"
  }
}
