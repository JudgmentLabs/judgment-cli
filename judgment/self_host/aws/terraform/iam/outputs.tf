output "ecs_task_execution_role_id" {
  value = aws_iam_role.ecs_task_execution_role.id
}

output "ecs_task_execution_role_arn" {
  value = aws_iam_role.ecs_task_execution_role.arn
}

output "ecs_task_execution_role_name" {
  value = aws_iam_role.ecs_task_execution_role.name
}

output "lambda_exec_role_id" {
  value = aws_iam_role.lambda_exec.id
}

output "lambda_exec_role_arn" {
  value = aws_iam_role.lambda_exec.arn
}

output "lambda_exec_role_name" {
  value = aws_iam_role.lambda_exec.name
}
