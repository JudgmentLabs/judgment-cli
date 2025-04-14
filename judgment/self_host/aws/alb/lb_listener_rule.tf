# resource "aws_lb_listener_rule" "https_websocket_rule" {
#   action {
#     order            = "1"
#     target_group_arn = "arn:aws:elasticloadbalancing:us-west-1:585008087243:targetgroup/websocket-server-target-group-1/7740f549750a2348"
#     type             = "forward"
#   }

#   certificate_arn = "${aws_lb_listener_certificate.tfer--arn-003A-aws-003A-acm-003A-us-002D-west-002D-1-003A-585008087243-003A-certificate-002F-3f4998c3-002D-64d6-002D-44b0-002D-a573-002D-eefc65e19a88.arn}"

#   condition {
#     http_header {
#       http_header_name = "Upgrade"
#       values           = ["websocket"]
#     }
#   }

#   listener_arn = "${data.terraform_remote_state.alb.outputs.aws_lb_listener_tfer--arn-003A-aws-003A-elasticloadbalancing-003A-us-002D-west-002D-1-003A-585008087243-003A-listener-002F-app-002F-judgment-002F-1c4bebdbd70870f0-002F-36b1ef14236d47d4_id}"
#   priority     = "1"

#   tags = {
#     Name = "websocket-redirect"
#   }

#   tags_all = {
#     Name = "websocket-redirect"
#   }
# }

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

# resource "aws_lb_listener_rule" "port8080_websocket_rule" {
#   action {
#     order            = "1"
#     target_group_arn = var.websocket_target_group_arn
#     type             = "forward"
#   }

#   condition {
#     http_header {
#       http_header_name = "Upgrade"
#       values           = ["websocket"]
#     }
#   }

#   listener_arn = "${aws_lb_listener.port8080_listener.arn}"
#   priority     = "1"

#   tags = {
#     Name = "websocket-redirect"
#   }

#   tags_all = {
#     Name = "websocket-redirect"
#   }
# }
