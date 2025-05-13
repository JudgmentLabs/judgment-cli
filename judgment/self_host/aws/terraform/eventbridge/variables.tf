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