output "judgment_lambda_arn" {
    value = aws_lambda_function.ecs_redeploy.arn
}

output "websockets_lambda_arn" {
    value = aws_lambda_function.ecs_redeploy.arn
}

output "run_eval_worker_lambda_arn" {
    value = aws_lambda_function.ecs_redeploy.arn
}
