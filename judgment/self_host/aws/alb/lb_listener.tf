# resource "aws_lb_listener" "https_listener" {
#   certificate_arn = "arn:aws:acm:us-west-1:585008087243:certificate/1311f5b9-c81f-4aa0-9f6a-446f20bb2e29"

#   default_action {
#     order            = "1"
#     target_group_arn = "arn:aws:elasticloadbalancing:us-west-1:585008087243:targetgroup/judgment-target-group/cee82395b653594e"
#     type             = "forward"
#   }

#   load_balancer_arn = "${data.terraform_remote_state.alb.outputs.aws_lb_tfer--judgment_id}"
#   port              = "443"
#   protocol          = "HTTPS"
#   ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
# }

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

# resource "aws_lb_listener" "port8080_listener" {
#   default_action {
#     order            = "1"
#     target_group_arn = "${aws_lb_target_group.judgment_ecs_target_group_2.arn}"
#     type             = "forward"
#   }

#   load_balancer_arn = "${aws_lb.judgment_lb.arn}"
#   port              = "8080"
#   protocol          = "HTTP"
# }

# resource "aws_lb_listener" "rabbitmq_listener" {
#   default_action {
#     target_group_arn = "${aws_lb_target_group.rabbitmq_queues.arn}"
#     type             = "forward"
#   }

#   load_balancer_arn = "${aws_lb.rabbitmq_networklb.arn}"
#   port              = "5672"
#   protocol          = "TCP"
# }
