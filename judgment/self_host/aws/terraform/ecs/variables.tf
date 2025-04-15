variable "subnet_ids" {
  type = list(string)
}

variable "cluster_name" {
  type    = string
  default = "judgmentlabs"
}

variable "backend_target_group_arn" {
  type = string
}

variable "backend_target_group_id" {
  type = string
}

variable "websocket_target_group_arn" {
  type = string
}

variable "websocket_target_group_id" {
  type = string
}

variable "judgment_ecs_sg_id" {
  type = string
}

variable "async_eval_worker_sg_id" {
  type = string
}

variable "ecs_task_execution_role_arn" {
  type = string
}

variable "judgment_lb_id" {
  type = string
}

variable "judgment_lb_arn" {
  type = string
}

variable "prod_api_keys_misc_version_arn" {
  type = string
}

variable "prod_api_keys_openai_version_arn" {
  type = string
}

variable "prod_creds_rabbitmq_version_arn" {
  type = string
}