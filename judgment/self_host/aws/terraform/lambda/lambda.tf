resource "aws_iam_role" "lambda_exec" {
  name = "lambda-ecs-redeploy-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Principal = {
        Service = "lambda.amazonaws.com"
      },
      Effect = "Allow"
    }]
  })
}

resource "aws_iam_role_policy" "ecs_redeploy_policy" {
  name = "ecs-redeploy"
  role = aws_iam_role.lambda_exec.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ecs:UpdateService",
          "ecs:DescribeServices"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ecs_redeploy.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.sns_from_primary_account.arn
}

resource "aws_lambda_permission" "allow_eventbridge_websockets" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.force_redeploy_websockets.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.sns_from_primary_account.arn
}

resource "aws_lambda_permission" "allow_eventbridge_run_eval_worker" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.force_redeploy_run_eval_worker.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.sns_from_primary_account.arn
}

resource "aws_lambda_function" "ecs_redeploy" {
  filename         = "lambda.zip" # zip containing your lambda_handler.py
  function_name    = "ECSForceRedeploy"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = filebase64sha256("lambda.zip")
}

resource "aws_lambda_function" "force_redeploy_websockets" {
  filename         = "force_redeploy_websockets.zip" # zip containing your lambda_handler.py
  function_name    = "ForceRedeployWebsockets"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = filebase64sha256("force_redeploy_websockets.zip")
}

resource "aws_lambda_function" "force_redeploy_run_eval_worker" {
  filename         = "force_redeploy_run_eval_worker.zip" # zip containing your lambda_handler.py
  function_name    = "ForceRedeployRunEvalWorker"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = filebase64sha256("force_redeploy_run_eval_worker.zip")
}
