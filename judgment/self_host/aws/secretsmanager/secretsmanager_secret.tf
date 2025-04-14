resource "aws_secretsmanager_secret" "prod_api_keys_misc" {
  description = "All other API keys and config env vars for Judgment Backend Server"
  name        = "prod/api-keys/misc"
}

resource "aws_secretsmanager_secret_version" "full_secret" {
  secret_id     = aws_secretsmanager_secret.prod_api_keys_misc.id
  secret_string = jsonencode({
    SUPABASE_URL = var.supabase_url
    SUPABASE_KEY = var.supabase_anon_key
    SUPABASE_SERVICE_ROLE_KEY = var.supabase_service_role_key
    SUPABASE_TABLE_NAME = "user_data"
    SUPABASE_JWT_SECRET = var.supabase_jwt_secret
    RABBITMQ_URL = var.rabbitmq_url
    RABBITMQ_USER = "admin"
    RABBITMQ_PASSWORD = "password12345"
    AWS_MQ_BROKER_NAME = var.rabbitmq_broker_name
    RABBITMQ_RUN_EVAL_QUEUE = "run_eval_queue"
    RABBITMQ_TRACE_EVAL_QUEUE = "trace_eval_queue"
    FRONTEND_URL = "https://app.judgmentlabs.ai"

  })
}

resource "aws_secretsmanager_secret" "prod_api_keys_openai" {
  description = "All LLM API Keys"
  name        = "prod/api-keys/openai"
}

resource "aws_secretsmanager_secret" "prod_api_keys_stripe" {
  description = "Stripe API keys"
  name = "prod/api-keys/stripe"
}

resource "aws_secretsmanager_secret" "prod_creds_rabbitmq" {
  description = "RabbitMQ username and password for prod AWS MQ"
  name        = "prod/creds/rabbitmq"
}

resource "aws_secretsmanager_secret_version" "full_secret" {
  secret_id     = aws_secretsmanager_secret.prod_creds_rabbitmq.id
  secret_string = jsonencode({
    RABBITMQ_USER = "admin"
    RABBITMQ_PASSWORD = "password12345"
  })
}