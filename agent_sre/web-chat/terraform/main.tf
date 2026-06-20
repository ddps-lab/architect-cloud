data "aws_caller_identity" "current" {}

data "aws_route53_zone" "zone" {
  name         = "${var.zone_name}."
  private_zone = false
}

locals {
  bucket_name = "copilot-chat-${data.aws_caller_identity.current.account_id}-apne2"
  web_dir     = "${path.module}/.."

  # 업로드할 정적 자산만 (스크립트/템플릿/테라폼 제외)
  web_files = toset([
    for f in fileset(local.web_dir, "*") :
    f if can(regex("\\.(html|js|css|png|jpe?g|ico|svg|map|woff2?)$", f))
  ])

  content_types = {
    html  = "text/html"
    js    = "application/javascript"
    css   = "text/css"
    png   = "image/png"
    jpg   = "image/jpeg"
    jpeg  = "image/jpeg"
    ico   = "image/x-icon"
    svg   = "image/svg+xml"
    map   = "application/json"
    woff  = "font/woff"
    woff2 = "font/woff2"
  }
}

###########
# S3 (정적 SPA, 비공개 — CloudFront OAC 로만 접근)
###########
resource "aws_s3_bucket" "chat" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_public_access_block" "chat" {
  bucket                  = aws_s3_bucket.chat.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "web" {
  for_each     = local.web_files
  bucket       = aws_s3_bucket.chat.id
  key          = each.value
  source       = "${local.web_dir}/${each.value}"
  source_hash  = filemd5("${local.web_dir}/${each.value}")
  content_type = lookup(local.content_types, lower(regex("[^.]+$", each.value)), "binary/octet-stream")
}

###########
# ACM 인증서 (기존 *.ddps.cloud 와일드카드 재사용, us-east-1)
###########
data "aws_acm_certificate" "cert" {
  provider    = aws.us_east_1
  domain      = var.zone_name
  statuses    = ["ISSUED"]
  most_recent = true
}

###########
# CloudFront + OAC
###########
resource "aws_cloudfront_origin_access_control" "chat" {
  name                              = "copilot-chat-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "chat" {
  enabled             = true
  default_root_object = "index.html"
  aliases             = [var.domain_name]

  origin {
    origin_id                = "ChatS3Origin"
    domain_name              = aws_s3_bucket.chat.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.chat.id
  }

  default_cache_behavior {
    target_origin_id       = "ChatS3Origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    # AWS managed "CachingOptimized"
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  # SPA: 403/404 를 index.html 로
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

###########
# S3 버킷 정책 (CloudFront OAC 만 읽기)
###########
data "aws_iam_policy_document" "chat_bucket" {
  statement {
    sid       = "AllowCloudFrontRead"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.chat.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.chat.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "chat" {
  bucket = aws_s3_bucket.chat.id
  policy = data.aws_iam_policy_document.chat_bucket.json
}

###########
# Route53 별칭 레코드 (도메인 → CloudFront)
###########
resource "aws_route53_record" "alias_a" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.chat.domain_name
    zone_id                = aws_cloudfront_distribution.chat.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "alias_aaaa" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = var.domain_name
  type    = "AAAA"
  alias {
    name                   = aws_cloudfront_distribution.chat.domain_name
    zone_id                = aws_cloudfront_distribution.chat.hosted_zone_id
    evaluate_target_health = false
  }
}
