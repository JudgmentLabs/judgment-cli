# Cluster outputs
output "ecs_cluster_id" {
  description = "The ID of the ECS cluster"
  value       = aws_ecs_cluster.judgmentlabs.id
}

# Service outputs
output "backend_service_id" {
  description = "The ID of the Judgment Backend service"
  value       = aws_ecs_service.JudgmentBackendServer.id
}

output "websocket_service_id" {
  description = "The ID of the Judgment WebSocket service"
  value       = aws_ecs_service.JudgmentWebSocketServer.id
}

output "run_eval_worker_service_id" {
  description = "The ID of the Run Eval Worker service"
  value       = aws_ecs_service.RunEvalWorker.id
}

output "trace_eval_worker_service_id" {
  description = "The ID of the Trace Eval Worker service"
  value       = aws_ecs_service.TraceEvalWorker.id
}

# Task Definition outputs
output "backend_task_definition_id" {
  description = "The ID of the Judgment Backend task definition"
  value       = aws_ecs_task_definition.judgment_backend_server_td.id
}

output "websocket_task_definition_id" {
  description = "The ID of the Judgment WebSocket task definition"
  value       = aws_ecs_task_definition.judgment_websockets_td.id
}

output "run_eval_worker_task_definition_id" {
  description = "The ID of the Run Eval Worker task definition"
  value       = aws_ecs_task_definition.run_eval_worker_td.id
}

output "trace_eval_worker_task_definition_id" {
  description = "The ID of the Trace Eval Worker task definition"
  value       = aws_ecs_task_definition.trace_eval_worker_td.id
}
