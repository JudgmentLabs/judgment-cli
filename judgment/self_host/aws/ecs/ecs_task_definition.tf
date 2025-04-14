resource "aws_ecs_task_definition" "judgment_websockets_td" {
  container_definitions = jsonencode([
    {
      cpu = 0
      environment = [
        {
          name  = "DEPLOYMENT_ENV"
          value = "PRODUCTION"
        }
      ]
      environmentFiles = []
      essential = true
      healthCheck = {
        command   = ["CMD-SHELL", "curl -f http://localhost:8001/health || exit 1"]
        interval  = 30
        retries   = 3
        timeout   = 5
      }
      image = "585008087243.dkr.ecr.us-west-1.amazonaws.com/judgment-websockets:latest"
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-create-group"  = "true"
          "awslogs-group"         = "/ecs/judgmentlabs-websockets"
          "awslogs-region"        = "us-west-1"
          "awslogs-stream-prefix" = "ecs"
          "max-buffer-size"       = "25m"
          "mode"                  = "non-blocking"
        }
        secretOptions = []
      }
      mountPoints = []
      name = "app"
      portMappings = [
        {
          appProtocol    = "http"
          containerPort  = 8001
          hostPort      = 8001
          name          = "app-8001-tcp-http"
          protocol      = "tcp"
        }
      ]
      systemControls = []
      ulimits = []
      volumesFrom = []
    }
  ])
  cpu                      = "4096"
  execution_role_arn       = var.ecs_task_execution_role_arn
  family                   = "judgmentlabs-websockets"
  memory                   = "16384"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  task_role_arn = var.ecs_task_execution_role_arn
}

resource "aws_ecs_task_definition" "run_eval_worker_td" {
  container_definitions = jsonencode([
    {
      cpu = 0
      environment = []
      essential = true
      healthCheck = {
        command     = ["CMD-SHELL", "test -f /tmp/healthy && grep -q 'healthy' /tmp/healthy || exit 1"]
        interval    = 60
        retries     = 3
        startPeriod = 300
        timeout     = 30
      }
      image = "585008087243.dkr.ecr.us-west-1.amazonaws.com/run-eval-worker:latest"
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-create-group"  = "true"
          "awslogs-group"         = "/ecs/run-eval-worker"
          "awslogs-region"        = "us-west-1"
          "awslogs-stream-prefix" = "ecs"
          "max-buffer-size"       = "25m"
          "mode"                  = "non-blocking"
        }
        secretOptions = []
      }
      mountPoints = []
      name = "app"
      portMappings = [
        {
          appProtocol    = "http"
          containerPort  = 80
          hostPort      = 80
          name          = "app-80-tcp"
          protocol      = "tcp"
        }
      ]
      systemControls = []
      volumesFrom = []
    }
  ])
  cpu                      = "2048"
  execution_role_arn       = var.ecs_task_execution_role_arn
  family                   = "run-eval-worker"
  memory                   = "8192"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  task_role_arn = var.ecs_task_execution_role_arn
}

resource "aws_ecs_task_definition" "judgment_backend_server_td" {
  container_definitions = jsonencode([
    {
      cpu = 0
      environment = [
        {
          name  = "DEPLOYMENT_ENV"
          value = "PRODUCTION"
        }
      ]
      environmentFiles = []
      essential = true
      healthCheck = {
        command   = ["CMD-SHELL", "curl -f http://localhost:80/health || exit 1"]
        interval  = 30
        retries   = 3
        timeout   = 5
      }
      image = "585008087243.dkr.ecr.us-west-1.amazonaws.com/judgement:latest"
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-create-group"   = "true"
          "awslogs-group"          = "/ecs/judgmentlabs"
          "awslogs-region"         = "us-west-1"
          "awslogs-stream-prefix"  = "ecs"
          "max-buffer-size"        = "25m"
          "mode"                   = "non-blocking"
        }
        secretOptions = []
      }
      mountPoints = []
      name = "app"
      portMappings = [
        {
          appProtocol    = "http"
          containerPort  = 80
          hostPort      = 80
          name          = "app-80-tcp-http"
          protocol      = "tcp"
        }
      ]
      systemControls = []
      ulimits = []
      volumesFrom = []
    }
  ])
  cpu                      = "4096"
  execution_role_arn       = var.ecs_task_execution_role_arn
  family                   = "judgmentlabs"
  memory                   = "16384"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  task_role_arn = var.ecs_task_execution_role_arn
}

resource "aws_ecs_task_definition" "trace_eval_worker_td" {
  container_definitions = jsonencode([
    {
      cpu = 0
      environment = []
      essential = true
      healthCheck = {
        command     = ["CMD-SHELL", "test -f /tmp/healthy && grep -q 'healthy' /tmp/healthy || exit 1"]
        interval    = 60
        retries     = 3
        startPeriod = 300
        timeout     = 30
      }
      image = "585008087243.dkr.ecr.us-west-1.amazonaws.com/trace-eval-worker:latest"
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-create-group"  = "true"
          "awslogs-group"         = "/ecs/trace-eval-worker"
          "awslogs-region"        = "us-west-1"
          "awslogs-stream-prefix" = "ecs"
          "max-buffer-size"       = "25m"
          "mode"                  = "non-blocking"
        }
        secretOptions = []
      }
      mountPoints = []
      name = "app"
      portMappings = [
        {
          appProtocol    = "http"
          containerPort  = 80
          hostPort      = 80
          name          = "app-80-tcp"
          protocol      = "tcp"
        }
      ]
      systemControls = []
      volumesFrom = []
    }
  ])
  cpu                      = "2048"
  execution_role_arn       = var.ecs_task_execution_role_arn
  family                   = "trace-eval-worker"
  memory                   = "8192"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  task_role_arn = var.ecs_task_execution_role_arn
}
