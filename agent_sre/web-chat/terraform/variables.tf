variable "region" {
  description = "S3/CloudFront 배포 리전 (S3 버킷)"
  type        = string
  default     = "ap-northeast-2"
}

variable "domain_name" {
  description = "채팅 사이트 커스텀 도메인"
  type        = string
  default     = "sre-agent-lab.ddps.cloud"
}

variable "zone_name" {
  description = "Route53 호스팅 영역 이름 (도메인의 상위 영역)"
  type        = string
  default     = "ddps.cloud"
}
