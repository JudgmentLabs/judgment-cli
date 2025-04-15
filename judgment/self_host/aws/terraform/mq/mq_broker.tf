resource "aws_mq_broker" "rabbitmq-judgment" {
  authentication_strategy    = "simple"
  auto_minor_version_upgrade = "true"
  broker_name                = "rabbitmq-judgment"

  deployment_mode = "CLUSTER_MULTI_AZ"

  encryption_options {
    use_aws_owned_key = "true"
  }

  engine_type        = "RabbitMQ"
  engine_version     = "3.13"
  host_instance_type = "mq.m5.large"

  logs {
    general = "false"
  }

  maintenance_window_start_time {
    day_of_week = "FRIDAY"
    time_of_day = "18:00"
    time_zone   = "UTC"
  }

  publicly_accessible = "true"
  storage_type        = "ebs"

  user {
    username = "admin"
    password = "password12345"
  }
}
