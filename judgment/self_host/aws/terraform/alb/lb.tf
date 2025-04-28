resource "aws_lb" "judgment_lb" {
  access_logs {
    bucket  = "judgment-alb-access-logs"
    enabled = "true"
  }

  desync_mitigation_mode           = "defensive"
  drop_invalid_header_fields       = "false"
  enable_cross_zone_load_balancing = "true"
  enable_deletion_protection       = "false"
  enable_http2                     = "true"
  enable_waf_fail_open             = "false"
  idle_timeout                     = "300"
  internal                         = "false"
  ip_address_type                  = "ipv4"
  load_balancer_type               = "application"
  name                             = "judgment"
  preserve_host_header             = "false"
  security_groups                  = [var.judgment_lb_sg_id]

  subnets = var.subnet_ids
}
