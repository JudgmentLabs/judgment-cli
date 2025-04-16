resource "aws_acm_certificate_validation" "validation" {
  certificate_arn = var.judgment_certificate_arn
}

resource "aws_lb_listener" "https_listener" {
  certificate_arn = aws_acm_certificate_validation.validation.certificate_arn

  default_action {
    order            = "1"
    target_group_arn = var.backend_target_group_arn
    type             = "forward"
  }

  load_balancer_arn = var.judgment_lb_arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}