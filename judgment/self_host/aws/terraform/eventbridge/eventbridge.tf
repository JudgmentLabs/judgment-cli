resource "aws_cloudwatch_event_permission" "allow_sns_from_primary_account" {
  principal    = "585008087243"
  statement_id = "AllowPrimaryAccountToPutEvents"
  action       = "events:PutEvents"
}

resource "aws_sns_topic_subscription" "eventbridge_to_sns" {
  topic_arn = "arn:aws:sns:us-west-1:585008087243:ECRJudgmentPush"
  protocol  = "https"
  endpoint  = "https://events.us-west-1.amazonaws.com/accounts/${data.aws_caller_identity.current.account_id}/event-bus/default"
}

data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_event_rule" "sns_from_primary_account_judgment" {
    name = "SNSFromPrimaryAccount"
    event_pattern = jsonencode({
        source = ["aws.sns"]
        "detail-type" = ["ECR Image Push"]
        "detail" = {
            "repository-name" = ["judgement"]
        }
    })
}

resource "aws_cloudwatch_event_rule" "sns_from_primary_account_websockets" {
    name = "SNSFromPrimaryAccountWebsockets"
    event_pattern = jsonencode({
        source = ["aws.sns"]
        "detail-type" = ["ECR Image Push"]
        "detail" = {
            "repository-name" = ["judgment-websockets"]
        }
    })
}

resource "aws_cloudwatch_event_rule" "sns_from_primary_account_run_eval_worker" {
    name = "SNSFromPrimaryAccountRunEvalWorker"
    event_pattern = jsonencode({
        source = ["aws.sns"]
        "detail-type" = ["ECR Image Push"]
        "detail" = {
            "repository-name" = ["run-eval-worker"]
        }
    })
}
