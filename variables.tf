variable "aws_access_key" {
  description = "AWS access key"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "AWS secret key"
  type        = string
  sensitive   = true
}

variable "aws_region" {
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

variable "input_bucket_name" {
  description = "Name for the S3 bucket where images are uploaded"
  default     = "image-processing-input"
}

variable "output_bucket_name" {
  description = "Name for the S3 bucket where processed results are stored"
  default     = "image-processing-output"
}
