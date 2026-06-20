terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# 기본: 서울 (S3 버킷)
provider "aws" {
  region = var.region
}

# CloudFront 용 ACM 인증서는 반드시 us-east-1 에 있어야 함
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
