output "prod_api_keys_misc_id" {
  value = aws_secretsmanager_secret.prod_api_keys_misc.id
}

output "prod_api_keys_misc_arn" {
  value = aws_secretsmanager_secret.prod_api_keys_misc.arn
}

output "prod_api_keys_openai_id" {
  value = aws_secretsmanager_secret.prod_api_keys_openai.id
}

output "prod_api_keys_openai_arn" {
  value = aws_secretsmanager_secret.prod_api_keys_openai.arn
}

output "prod_api_keys_stripe_id" {
  value = aws_secretsmanager_secret.prod_api_keys_stripe.id
}

output "prod_api_keys_stripe_arn" {
  value = aws_secretsmanager_secret.prod_api_keys_stripe.arn
}

output "prod_creds_rabbitmq_id" {
  value = aws_secretsmanager_secret.prod_creds_rabbitmq.id
}

output "prod_creds_rabbitmq_arn" {
  value = aws_secretsmanager_secret.prod_creds_rabbitmq.arn
}