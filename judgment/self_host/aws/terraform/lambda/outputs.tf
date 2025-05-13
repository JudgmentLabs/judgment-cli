output "judgment_lambda_arn" {
    value = aws_lambda_function.force_redeploy_judgment.arn
}

# output "websockets_lambda_arn" {
#     value = aws_lambda_function.force_redeploy_websockets.arn
# }

# output "run_eval_worker_lambda_arn" {
#     value = aws_lambda_function.force_redeploy_run_eval_worker.arn
# }
