output "aws_mq_broker_rabbitmq-judgment_id" {
  value = aws_mq_broker.rabbitmq-judgment.id
}

output "aws_mq_broker_rabbitmq-judgment_url" {
  value = regex("^(?:[a-zA-Z]+://)?([^:]+)", aws_mq_broker.rabbitmq-judgment.instances[0].endpoints[0])[0]
  # Exclude protocol and port
}

output "aws_mq_broker_rabbitmq-judgment_name" {
  value = aws_mq_broker.rabbitmq-judgment.broker_name
}