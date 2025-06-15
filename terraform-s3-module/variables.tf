variable "project" {
  description = "Project name (e.g., projectA)"
  type        = string
  default     = ""
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "bucket_suffix" {
  description = "Suffix to append to the bucket name"
  type        = string
  default     = "bucket"
}

variable "force_destroy" {
  description = "Force destroy the bucket on terraform destroy"
  type        = bool
  default     = true
}
