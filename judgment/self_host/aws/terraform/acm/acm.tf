resource "aws_acm_certificate" "judgment_certificate" {
  domain_name       = var.domain_name
  validation_method = "DNS"
}