# resource "aws_lb_target_group" "judgment_ecs_target_group_2" {
#   deregistration_delay = "300"

#   health_check {
#     enabled             = "true"
#     healthy_threshold   = "5"
#     interval            = "30"
#     matcher             = "200"
#     path                = "/"
#     port                = "traffic-port"
#     protocol            = "HTTP"
#     timeout             = "5"
#     unhealthy_threshold = "2"
#   }

#   ip_address_type               = "ipv4"
#   load_balancing_algorithm_type = "round_robin"
#   name                          = "judgment-ecs-target-group-2"
#   port                          = "8080"
#   protocol                      = "HTTP"
#   protocol_version              = "HTTP1"
#   slow_start                    = "0"

#   stickiness {
#     cookie_duration = "86400"
#     enabled         = "false"
#     type            = "lb_cookie"
#   }

#   target_type = "ip"
#   vpc_id      = "judgment_vpc"
# }

# resource "aws_lb_target_group" "ecs_test_listener" {
#   deregistration_delay = "300"

#   health_check {
#     enabled             = "true"
#     healthy_threshold   = "5"
#     interval            = "30"
#     matcher             = "200"
#     path                = "/"
#     port                = "traffic-port"
#     protocol            = "HTTP"
#     timeout             = "5"
#     unhealthy_threshold = "2"
#   }

#   ip_address_type               = "ipv4"
#   load_balancing_algorithm_type = "round_robin"
#   name                          = "judgment-ecs-test-listener"
#   port                          = "80"
#   protocol                      = "HTTP"
#   protocol_version              = "HTTP1"
#   slow_start                    = "0"

#   stickiness {
#     cookie_duration = "86400"
#     enabled         = "false"
#     type            = "lb_cookie"
#   }

#   target_type = "ip"
#   vpc_id      = "judgment_vpc"
# }

resource "aws_lb_target_group" "judgment_target_group" {
  deregistration_delay = "300"

  health_check {
    enabled             = "true"
    healthy_threshold   = "5"
    interval            = "30"
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = "5"
    unhealthy_threshold = "2"
  }

  ip_address_type               = "ipv4"
  load_balancing_algorithm_type = "round_robin"
  name                          = "judgment-target-group"
  port                          = "80"
  protocol                      = "HTTP"
  protocol_version              = "HTTP1"
  slow_start                    = "0"

  stickiness {
    cookie_duration = "86400"
    enabled         = "false"
    type            = "lb_cookie"
  }

  target_type = "ip"
  vpc_id      = var.judgment_vpc_id
}

# resource "aws_lb_target_group" "rabbitmq_queues" {
#   connection_termination = "false"
#   deregistration_delay   = "300"

#   health_check {
#     enabled             = "true"
#     healthy_threshold   = "5"
#     interval            = "30"
#     port                = "traffic-port"
#     protocol            = "TCP"
#     timeout             = "10"
#     unhealthy_threshold = "2"
#   }

#   ip_address_type    = "ipv4"
#   name               = "rabbitmq-queues"
#   port               = "5672"
#   preserve_client_ip = "false"
#   protocol           = "TCP"
#   proxy_protocol_v2  = "false"

#   stickiness {
#     cookie_duration = "0"
#     enabled         = "false"
#     type            = "source_ip"
#   }

#   target_type = "ip"
#   vpc_id      = "vpc-051ded8ab85c23058"
# }

# resource "aws_lb_target_group" "tfer--tg-002D-judgem-002D-JudgmentBackendStagi-002D-2" {
#   deregistration_delay = "300"

#   health_check {
#     enabled             = "true"
#     healthy_threshold   = "5"
#     interval            = "30"
#     matcher             = "200"
#     path                = "/"
#     port                = "traffic-port"
#     protocol            = "HTTP"
#     timeout             = "5"
#     unhealthy_threshold = "2"
#   }

#   ip_address_type               = "ipv4"
#   load_balancing_algorithm_type = "round_robin"
#   name                          = "tg-judgem-JudgmentBackendStagi-2"
#   port                          = "80"
#   protocol                      = "HTTP"
#   protocol_version              = "HTTP1"
#   slow_start                    = "0"

#   stickiness {
#     cookie_duration = "86400"
#     enabled         = "false"
#     type            = "lb_cookie"
#   }

#   target_type = "ip"
#   vpc_id      = "judgment_vpc"
# }

resource "aws_lb_target_group" "websocket_server_target_group_1" {
  deregistration_delay = "300"

  health_check {
    enabled             = "true"
    healthy_threshold   = "5"
    interval            = "30"
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = "5"
    unhealthy_threshold = "2"
  }

  ip_address_type               = "ipv4"
  load_balancing_algorithm_type = "round_robin"
  name                          = "websocket-server-target-group-1"
  port                          = "8001"
  protocol                      = "HTTP"
  protocol_version              = "HTTP1"
  slow_start                    = "0"

  stickiness {
    cookie_duration = "86400"
    enabled         = "false"
    type            = "lb_cookie"
  }

  target_type = "ip"
  vpc_id      = var.judgment_vpc_id
}

# resource "aws_lb_target_group" "tfer--websocket-002D-server-002D-target-002D-group-002D-2" {
#   deregistration_delay = "300"

#   health_check {
#     enabled             = "true"
#     healthy_threshold   = "5"
#     interval            = "30"
#     matcher             = "200"
#     path                = "/health"
#     port                = "traffic-port"
#     protocol            = "HTTP"
#     timeout             = "5"
#     unhealthy_threshold = "2"
#   }

#   ip_address_type               = "ipv4"
#   load_balancing_algorithm_type = "round_robin"
#   name                          = "websocket-server-target-group-2"
#   port                          = "8001"
#   protocol                      = "HTTP"
#   protocol_version              = "HTTP1"
#   slow_start                    = "0"

#   stickiness {
#     cookie_duration = "86400"
#     enabled         = "false"
#     type            = "lb_cookie"
#   }

#   target_type = "ip"
#   vpc_id      = "vpc-051ded8ab85c23058"
# }

# resource "aws_lb_target_group" "tfer--websockets-002D-test-002D-ec2" {
#   deregistration_delay = "300"

#   health_check {
#     enabled             = "true"
#     healthy_threshold   = "5"
#     interval            = "30"
#     matcher             = "200"
#     path                = "/"
#     port                = "traffic-port"
#     protocol            = "HTTP"
#     timeout             = "5"
#     unhealthy_threshold = "2"
#   }

#   ip_address_type               = "ipv4"
#   load_balancing_algorithm_type = "round_robin"
#   name                          = "websockets-test-ec2"
#   port                          = "444"
#   protocol                      = "HTTPS"
#   protocol_version              = "HTTP1"
#   slow_start                    = "0"

#   stickiness {
#     cookie_duration = "86400"
#     enabled         = "true"
#     type            = "lb_cookie"
#   }

#   target_type = "instance"
#   vpc_id      = "vpc-051ded8ab85c23058"
# }

# resource "aws_lb_target_group" "tfer--websockets-002D-test-002D-ec2-002D-v2" {
#   deregistration_delay = "300"

#   health_check {
#     enabled             = "true"
#     healthy_threshold   = "5"
#     interval            = "30"
#     matcher             = "200"
#     path                = "/"
#     port                = "traffic-port"
#     protocol            = "HTTP"
#     timeout             = "5"
#     unhealthy_threshold = "2"
#   }

#   ip_address_type               = "ipv4"
#   load_balancing_algorithm_type = "round_robin"
#   name                          = "websockets-test-ec2-v2"
#   port                          = "8000"
#   protocol                      = "HTTP"
#   protocol_version              = "HTTP1"
#   slow_start                    = "0"

#   stickiness {
#     cookie_duration = "86400"
#     enabled         = "false"
#     type            = "lb_cookie"
#   }

#   target_type = "instance"
#   vpc_id      = "vpc-051ded8ab85c23058"
# }

# resource "aws_lb_target_group" "tfer--websockets-002D-test-002D-lambda" {
#   health_check {
#     enabled             = "false"
#     healthy_threshold   = "5"
#     interval            = "35"
#     matcher             = "200"
#     path                = "/"
#     timeout             = "30"
#     unhealthy_threshold = "2"
#   }

#   ip_address_type                    = "ipv4"
#   lambda_multi_value_headers_enabled = "false"
#   name                               = "websockets-test-lambda"
#   target_type                        = "lambda"
# }
