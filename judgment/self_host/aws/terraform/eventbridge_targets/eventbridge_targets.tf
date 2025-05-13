resource "aws_cloudwatch_event_target" "sns_from_primary_account_target_judgment" {
    rule = var.cloudwatch_event_rule_arn_judgment
    target_id = "LambdaForceRedeployJudgment"
    arn = var.judgment_lambda_arn
}

resource "aws_cloudwatch_event_target" "sns_from_primary_account_target_websockets" {
    rule = var.cloudwatch_event_rule_arn_websockets
    target_id = "LambdaECSForceRedeployWebsockets"
    arn = var.websockets_lambda_arn
}

resource "aws_cloudwatch_event_target" "sns_from_primary_account_target_run_eval_worker" {
    rule = var.cloudwatch_event_rule_arn_run_eval_worker
    target_id = "LambdaECSForceRedeployRunEvalWorker"
    arn = var.run_eval_worker_lambda_arn
} 