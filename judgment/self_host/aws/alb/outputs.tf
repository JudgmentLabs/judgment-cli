output "port80_listener_id" {
  value = "${aws_lb_listener.port80_listener.id}"
}

# output "port8080_listener_id" {
#   value = "${aws_lb_listener.port8080_listener.id}"
# }

# output "rabbitmq_listener_id" {
#   value = "${aws_lb_listener.rabbitmq_listener.id}"
# }

output "port80_websocket_rule_id" {
  value = "${aws_lb_listener_rule.port80_websocket_rule.id}"
}

# output "port8080_websocket_rule_id" {
#   value = "${aws_lb_listener_rule.port8080_websocket_rule.id}"
# }

output "judgment_target_group_id" {
  value = "${aws_lb_target_group.judgment_target_group.id}"
}

output "judgment_target_group_arn" {
  value = "${aws_lb_target_group.judgment_target_group.arn}"
}

output "websocket_server_target_group_1_id" {
  value = "${aws_lb_target_group.websocket_server_target_group_1.id}"
}

output "websocket_server_target_group_1_arn" {
  value = "${aws_lb_target_group.websocket_server_target_group_1.arn}"
}

output "judgment_lb_id" {
  value = "${aws_lb.judgment_lb.id}"
}

output "judgment_lb_arn" {
  value = "${aws_lb.judgment_lb.arn}"
}

# output "rabbitmq_network_lb_id" {
#   value = "${aws_lb.rabbitmq_networklb.id}"
# }

output "judgment_lb_dns_name" {
  value = "${aws_lb.judgment_lb.dns_name}"
}
