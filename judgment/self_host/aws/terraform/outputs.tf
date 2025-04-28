output "judgment_lb_dns_name" {
  value = module.alb.judgment_lb_dns_name
}

output "judgment_lb_arn" {
  value = module.alb.judgment_lb_arn
}

output "judgment_certificate_arn" {
  value = module.acm.judgment_certificate_arn
}

output "backend_target_group_arn" {
  value = module.alb.judgment_target_group_arn
}

output "websocket_target_group_arn" {
  value = module.alb.websocket_server_target_group_1_arn
}

output "judgment_certificate_domain_validation_name" {
    value = module.acm.dns_name
}

output "judgment_certificate_domain_validation_value" {
    value = module.acm.dns_value
}

output "domain_name" {
    value = var.domain_name
}
