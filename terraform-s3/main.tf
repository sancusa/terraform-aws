terraform {

  required_providers {

    aws = {

      source  = "hashicorp/aws"

      version = "~> 5.98"

    }

  }



  required_version = ">= 1.2.0"

}



provider "aws" {

  region  = "us-east-1"

}



resource "aws_instance" "example_server" {

  ami           = "ami-0953476d60561c955"

  instance_type = "t2.micro"



  tags = {

    Name = "TestExample"

  }

}