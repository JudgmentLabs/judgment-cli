resource "aws_secretsmanager_secret" "prod_api_keys_misc" {
  description = "All other API keys and config env vars for Judgment Backend Server"
  name        = "prod/api-keys/misc"
}

resource "aws_secretsmanager_secret_version" "prod_api_keys_misc_version" {
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
    AWS_MQ_BROKER_ID = var.rabbitmq_broker_id
    RABBITMQ_RUN_EVAL_QUEUE = "run_eval_queue"
    RABBITMQ_TRACE_EVAL_QUEUE = "trace_eval_queue"
    FRONTEND_URL = "https://app.judgmentlabs.ai"
    BACKEND_URL = var.judgment_lb_dns_name
    PYTHON_PATH = "."
    CUSTOM_MODEL_INPUT_TOKEN_COST = 0.0000025
    CUSTOM_MODEL_OUTPUT_TOKEN_COST = 0.00001
    LITELLM_LOG = "DEBUG"
    "TEST!" = "hehetesttest"
    LANGFUSE_HOST = "https://us.cloud.langfuse.com"
    LANGFUSE_PUBLIC_KEY = var.langfuse_public_key
    LANGFUSE_SECRET_KEY = var.langfuse_secret_key
  })
}

resource "aws_secretsmanager_secret" "prod_api_keys_openai" {
  description = "All LLM API Keys"
  name        = "prod/api-keys/openai"
}

resource "aws_secretsmanager_secret_version" "prod_api_keys_openai_version" {
  secret_id     = aws_secretsmanager_secret.prod_api_keys_openai.id
  secret_string = jsonencode({
    OPENAI_API_KEY = var.openai_api_key
    TOGETHERAI_API_KEY = var.togetherai_api_key
    ANTHROPIC_API_KEY = var.anthropic_api_key
  })
}

resource "aws_secretsmanager_secret" "prod_api_keys_stripe" {
  description = "Stripe API keys"
  name = "prod/api-keys/stripe"
}

resource "aws_secretsmanager_secret_version" "prod_api_keys_stripe_version" {
  secret_id     = aws_secretsmanager_secret.prod_api_keys_stripe.id
  secret_string = jsonencode({
  })
}

resource "aws_secretsmanager_secret" "prod_creds_rabbitmq" {
  description = "RabbitMQ username and password for prod AWS MQ"
  name        = "prod/creds/rabbitmq"
}

resource "aws_secretsmanager_secret_version" "prod_creds_rabbitmq_version" {
  secret_id     = aws_secretsmanager_secret.prod_creds_rabbitmq.id
  secret_string = jsonencode({
    RABBITMQ_USER = "admin"
    RABBITMQ_PASSWORD = "password12345"
  })
}
