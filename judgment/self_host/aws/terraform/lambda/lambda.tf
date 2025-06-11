resource "aws_lambda_permission" "allow_sns_judgment" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.force_redeploy_judgment.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = "arn:aws:sns:us-west-1:585008087243:ECRJudgmentPush"
}

resource "aws_sns_topic_subscription" "repo_a_sub" {
  topic_arn = "arn:aws:sns:us-west-1:585008087243:ECRJudgmentPush"
  protocol  = "lambda"
  endpoint  = aws_lambda_function.force_redeploy_judgment.arn
}

resource "aws_lambda_function" "force_redeploy_judgment" {
  filename         = "${path.module}/force_redeploy.zip"
  function_name    = "ForceRedeploy"
  role             = var.lambda_exec_role_arn
  handler          = "force_redeploy.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = filebase64sha256("${path.module}/force_redeploy.zip")
  environment {
    variables = {
      ECR_CLUSTER_NAME = "judgmentlabs"
      JUDGMENT_REPO = "judgement"
      JUDGMENT_WEBSOCKETS_REPO = "judgment-websockets"
      RUN_EVAL_WORKER_REPO = "run-eval-worker"
      JUDGMENT_SERVICE = "JudgmentBackendServer"
      JUDGMENT_WEBSOCKETS_SERVICE = "JudgmentWebSocketServer"
      RUN_EVAL_WORKER_SERVICE = "RunEvalWorker"
    }
  }
}
