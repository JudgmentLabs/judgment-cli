resource "aws_lb_listener" "port80_listener" {
  default_action {
    order            = "1"
    target_group_arn = var.backend_target_group_arn
    type             = "forward"
  }

  load_balancer_arn = "${aws_lb.judgment_lb.arn}"
  port              = "80"
  protocol          = "HTTP"
}
