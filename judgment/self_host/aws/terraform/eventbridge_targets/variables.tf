variable "judgment_lambda_arn" {
    type = string
    description = "The ARN of the judgment lambda function"
}

variable "websockets_lambda_arn" {
    type = string
    description = "The ARN of the websockets lambda function"
}

variable "run_eval_worker_lambda_arn" {
    type = string
    description = "The ARN of the run eval worker lambda function"
}

variable "cloudwatch_event_rule_name_judgment" {
    type = string
    description = "The name of the judgment event rule"
}

variable "cloudwatch_event_rule_name_websockets" {
    type = string
    description = "The name of the websockets event rule"
}

variable "cloudwatch_event_rule_name_run_eval_worker" {
    type = string
    description = "The name of the run eval worker event rule"
} 