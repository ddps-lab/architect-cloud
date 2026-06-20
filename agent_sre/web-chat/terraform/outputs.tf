output "chat_site_url" {
  description = "커스텀 도메인 채팅 사이트"
  value       = "https://${var.domain_name}"
}

output "cloudfront_domain" {
  description = "CloudFront 배포 도메인 (직접 접근용)"
  value       = "https://${aws_cloudfront_distribution.chat.domain_name}"
}

output "chat_bucket" {
  value = aws_s3_bucket.chat.id
}
