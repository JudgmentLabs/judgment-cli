output "async_eval_worker_id" {
  value = aws_security_group.async_eval_worker.id
}

output "judgment_ecs_sg_id" {
  value = aws_security_group.judgment_ecs_sg.id
}

output "judgment_lb_sg_id" {
  value = aws_security_group.judgment_lb_sg.id
}

output "websockets_ecs_sg_id" {
  value = aws_security_group.websockets_ecs_sg.id
}
