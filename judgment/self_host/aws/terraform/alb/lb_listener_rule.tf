resource "aws_lb_listener_rule" "port80_websocket_rule" {
  action {
    order            = "1"
    target_group_arn = var.websocket_target_group_arn
    type             = "forward"
  }

  condition {
    http_header {
      http_header_name = "Upgrade"
      values           = ["websocket"]
    }
  }

  listener_arn = "${aws_lb_listener.port80_listener.arn}"
  priority     = "1"

  tags = {
    Name = "websocket-redirect"
  }

  tags_all = {
    Name = "websocket-redirect"
  }
}
