resource "aws_ecs_service" "JudgmentBackendServer" {
  cluster = var.cluster_name

  deployment_maximum_percent         = "200"
  deployment_minimum_healthy_percent = "100"
  desired_count                      = "3"
  enable_ecs_managed_tags            = "true"
  enable_execute_command             = "false"
  health_check_grace_period_seconds  = "0"
  launch_type                        = "FARGATE"

  load_balancer {
    container_name   = "app"
    container_port   = "80"
    target_group_arn = var.backend_target_group_arn
  }

  name = "JudgmentBackendServer"

  network_configuration {
    assign_public_ip = "true"
    security_groups  = [var.judgment_ecs_sg_id]
    subnets          = var.subnet_ids
  }

  platform_version    = "1.4.0"
  scheduling_strategy = "REPLICA"

  task_definition = aws_ecs_task_definition.judgment_backend_server_td.arn
}

# Backend Service Autoscaling
resource "aws_appautoscaling_target" "backend_target" {
  max_capacity       = 10
  min_capacity       = 2
  resource_id        = "service/${var.cluster_name}/${aws_ecs_service.JudgmentBackendServer.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "backend_scale_policy" {
  name               = "backend-scale-policy"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.backend_target.resource_id
  scalable_dimension = aws_appautoscaling_target.backend_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.backend_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 0.5
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label        = "app/judgment/${split("/", var.judgment_lb_id)[2]}/targetgroup/judgment-target-group/${split("/", var.backend_target_group_id)[2]}"
    }
    scale_in_cooldown  = 300
    scale_out_cooldown = 120
  }
}

resource "aws_ecs_service" "JudgmentWebSocketServer" {
  cluster = var.cluster_name

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  deployment_maximum_percent         = "200"
  deployment_minimum_healthy_percent = "100"
  desired_count                      = "2"
  enable_ecs_managed_tags            = "true"
  enable_execute_command             = "false"
  health_check_grace_period_seconds  = "0"
  launch_type                        = "FARGATE"

  load_balancer {
    container_name   = "app"
    container_port   = "8001"
    target_group_arn = var.websocket_target_group_arn
  }

  name = "JudgmentWebSocketServer"

  network_configuration {
    assign_public_ip = "true"
    security_groups  = [var.judgment_ecs_sg_id]
    subnets          = var.subnet_ids
  }

  platform_version    = "1.4.0"
  scheduling_strategy = "REPLICA"
  task_definition     = aws_ecs_task_definition.judgment_websockets_td.arn
}

# WebSocket Service Autoscaling
resource "aws_appautoscaling_target" "websocket_target" {
  max_capacity       = 10
  min_capacity       = 2
  resource_id        = "service/${var.cluster_name}/${aws_ecs_service.JudgmentWebSocketServer.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "websocket_scale_policy" {
  name               = "websocket-scale-policy"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.websocket_target.resource_id
  scalable_dimension = aws_appautoscaling_target.websocket_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.websocket_target.service_namespace

  target_tracking_scaling_policy_configuration {
    target_value = 0.5
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label        = "app/judgment/${split("/", var.judgment_lb_id)[2]}/targetgroup/websocket-server-target-group-1/${split("/", var.websocket_target_group_id)[2]}"
    }
    scale_in_cooldown  = 300
    scale_out_cooldown = 120
  }
}

resource "aws_ecs_service" "RunEvalWorker" {

  capacity_provider_strategy {
    base              = "0"
    capacity_provider = "FARGATE"
    weight            = "1"
  }

  cluster = var.cluster_name

  deployment_circuit_breaker {
    enable   = "true"
    rollback = "true"
  }

  deployment_controller {
    type = "ECS"
  }

  deployment_maximum_percent         = "200"
  deployment_minimum_healthy_percent = "100"
  desired_count                      = "3"
  enable_ecs_managed_tags            = "true"
  enable_execute_command             = "false"
  health_check_grace_period_seconds  = "0"
  name                               = "RunEvalWorker"

  network_configuration {
    assign_public_ip = "true"
    security_groups  = [var.async_eval_worker_sg_id]
    subnets          = var.subnet_ids
  }

  platform_version    = "1.4.0"
  scheduling_strategy = "REPLICA"
  task_definition     = aws_ecs_task_definition.run_eval_worker_td.arn
}

resource "aws_ecs_service" "TraceEvalWorker" {

  capacity_provider_strategy {
    base              = "0"
    capacity_provider = "FARGATE"
    weight            = "1"
  }

  cluster = var.cluster_name

  deployment_circuit_breaker {
    enable   = "true"
    rollback = "true"
  }

  deployment_controller {
    type = "ECS"
  }

  deployment_maximum_percent         = "200"
  deployment_minimum_healthy_percent = "100"
  desired_count                      = "3"
  enable_ecs_managed_tags            = "true"
  enable_execute_command             = "false"
  health_check_grace_period_seconds  = "0"
  name                               = "TraceEvalWorker"

  network_configuration {
    assign_public_ip = "true"
    security_groups  = [var.async_eval_worker_sg_id]
    subnets          = var.subnet_ids
  }

  platform_version    = "1.4.0"
  scheduling_strategy = "REPLICA"
  task_definition     = aws_ecs_task_definition.trace_eval_worker_td.arn
}
