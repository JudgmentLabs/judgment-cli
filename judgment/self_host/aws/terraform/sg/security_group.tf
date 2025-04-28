resource "aws_security_group" "async_eval_worker" {
  description = "Security group for Async Eval Worker"
  name        = "async-eval-worker-sg"
  vpc_id      = var.judgment_vpc_id
}

resource "aws_vpc_security_group_egress_rule" "async_eval_worker_egress" {
  security_group_id = aws_security_group.async_eval_worker.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_security_group" "judgment_ecs_sg" {
  description = "Judgment ECS Service Security Group"
  name        = "judgment-ecs-service-sg"
  vpc_id      = var.judgment_vpc_id
}

resource "aws_vpc_security_group_egress_rule" "judgment_ecs_egress" {
  security_group_id = aws_security_group.judgment_ecs_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "judgment_ecs_ingress" {
  security_group_id = aws_security_group.judgment_ecs_sg.id
  from_port         = 0
  ip_protocol       = "tcp"
  to_port           = 65535
  referenced_security_group_id = aws_security_group.judgment_lb_sg.id
}

resource "aws_security_group" "judgment_lb_sg" {
  description = "Judgment Security Group"
  name        = "judgment-sg"
  vpc_id      = var.judgment_vpc_id
}

resource "aws_vpc_security_group_egress_rule" "judgment_lb_egress" {
  security_group_id = aws_security_group.judgment_lb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "judgment_lb_ingress_443" {
  security_group_id = aws_security_group.judgment_lb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "judgment_lb_ingress_443_ipv6" {
  security_group_id = aws_security_group.judgment_lb_sg.id
  cidr_ipv6         = "::/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "judgment_lb_ingress_80" {
  security_group_id = aws_security_group.judgment_lb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "judgment_lb_ingress_80_ipv6" {
  security_group_id = aws_security_group.judgment_lb_sg.id
  cidr_ipv6         = "::/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "judgment_lb_ingress_8080" {
  security_group_id = aws_security_group.judgment_lb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 8080
  ip_protocol       = "tcp"
  to_port           = 8080
}

resource "aws_vpc_security_group_ingress_rule" "judgment_lb_ingress_8080_ipv6" {
  security_group_id = aws_security_group.judgment_lb_sg.id
  cidr_ipv6         = "::/0"
  from_port         = 8080
  ip_protocol       = "tcp"
  to_port           = 8080
}

resource "aws_security_group" "websockets_ecs_sg" {
  description = "WebSocket ECS Service Security Group"
  name        = "websockets-ecs-service-sg"
  vpc_id      = var.judgment_vpc_id
}

resource "aws_vpc_security_group_egress_rule" "websockets_ecs_egress" {
  security_group_id = aws_security_group.websockets_ecs_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "websockets_ecs_ingress" {
  security_group_id = aws_security_group.websockets_ecs_sg.id
  from_port         = 0
  ip_protocol       = "tcp"
  to_port           = 65535
  referenced_security_group_id = aws_security_group.judgment_lb_sg.id
}
