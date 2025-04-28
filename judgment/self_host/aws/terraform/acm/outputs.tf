output "dns_name" {
  value = one(aws_acm_certificate.judgment_certificate.domain_validation_options).resource_record_name
}

output "dns_value" {
  value = one(aws_acm_certificate.judgment_certificate.domain_validation_options).resource_record_value
}

output "judgment_certificate_arn" {
  value = aws_acm_certificate.judgment_certificate.arn
}