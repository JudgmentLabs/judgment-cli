output "cloudwatch_event_rule_name_judgment" {
  value = aws_cloudwatch_event_rule.sns_from_primary_account_judgment.name
}

output "cloudwatch_event_rule_name_websockets" {
  value = aws_cloudwatch_event_rule.sns_from_primary_account_websockets.name
}

output "cloudwatch_event_rule_name_run_eval_worker" {
  value = aws_cloudwatch_event_rule.sns_from_primary_account_run_eval_worker.name
}
