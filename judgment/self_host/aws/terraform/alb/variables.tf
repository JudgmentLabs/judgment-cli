variable "subnet_ids" {
  type = list(string)
}

variable "judgment_vpc_id" {
  type = string
}

variable "judgment_lb_sg_id" {
  type = string
}

variable "backend_target_group_arn" {
  type = string
}

variable "websocket_target_group_arn" {
  type = string
}
