provider "aws" {
  region = "us-east-1"
}

locals {
  name_suffix = "terraform-ecs-cluster"
  common_tags = {
    IAC          = "terraform"
    AppName      = "terraform-ecs-cluster"
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

# Public subnets
resource "aws_subnet" "public" {
  count             = 2
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.${count.index}.0/24"
  availability_zone = "us-east-1${count.index == 0 ? "a" : "b"}"
  map_public_ip_on_launch = true
  
  tags = merge(local.common_tags, {
    Name = "subnet-public-${count.index}-${local.name_suffix}"
  })
}

# Private subnets for Fargate tasks
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = "us-east-1${count.index == 0 ? "a" : "b"}"
  
  tags = merge(local.common_tags, {
    Name = "subnet-private-${count.index}-${local.name_suffix}"
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
  domain = "vpc"
  
  tags = merge(local.common_tags, {
    Name = "eip-nat-${local.name_suffix}"
  })
}

# NAT Gateway (only one for cost optimization)
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  
  tags = merge(local.common_tags, {
    Name = "nat-${local.name_suffix}"
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
  vpc_id = aws_vpc.vpc.id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  
  tags = merge(local.common_tags, {
    Name = "rt-private-${local.name_suffix}"
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
  route_table_id = aws_route_table.private.id
}

# Security Group for ECS Tasks
resource "aws_security_group" "ecs_tasks" {
  name        = "ecs-tasks-sg-${local.name_suffix}"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.vpc.id
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = merge(local.common_tags, {
    Name = "ecs-tasks-sg-${local.name_suffix}"
  })
}

# ECS Cluster
resource "aws_ecs_cluster" "cluster" {
  name = "ecs-cluster-${local.name_suffix}"
  
  setting {
    name  = "containerInsights"
    value = "disabled"  # Cost optimization
  }
  
  tags = local.common_tags
}

# ECS Capacity Provider
resource "aws_ecs_cluster_capacity_providers" "fargate" {
  cluster_name = aws_ecs_cluster.cluster.name
  
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
  
  default_capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"  # Cost optimization
    weight            = 1
  }
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs-task-execution-role-${local.name_suffix}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
  
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${local.name_suffix}"
  retention_in_days = 7  # Cost optimization
  
  tags = local.common_tags
}

# ECR Repository
resource "aws_ecr_repository" "app_repo" {
  name = "app-repo-${local.name_suffix}"

  tags = merge(local.common_tags, {
    Name = "ecr-repo-${local.name_suffix}"
  })
}

# ECS Task Definition
resource "aws_ecs_task_definition" "app" {
  family                   = "app-task-${local.name_suffix}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  container_definitions    = jsonencode([
    {
      name      = "app-container"
      image     = "${aws_ecr_repository.app_repo.repository_url}:latest"
      essential = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs_logs.name
          awslogs-region        = "us-east-1"
          awslogs-stream-prefix = "app"
        }
      }
    }
  ])

  tags = local.common_tags
}

# ECS Service
resource "aws_ecs_service" "app_service" {
  name            = "app-service-${local.name_suffix}"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.app.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = aws_subnet.private[*].id
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  tags = local.common_tags
}

# Outputs
output "ecs_cluster_name" {
  value = aws_ecs_cluster.cluster.name
}

output "ecs_cluster_arn" {
  value = aws_ecs_cluster.cluster.arn
}

output "vpc_id" {
  value = aws_vpc.vpc.id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "ecr_repo_url" {
  value = aws_ecr_repository.app_repo.repository_url
}

output "ecs_service_name" {
  value = aws_ecs_service.app_service.name
}
