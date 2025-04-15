module alb {
  source = "./alb"
  subnet_ids = module.vpc.all_subnets
  judgment_vpc_id = module.vpc.aws_vpc_judgment_vpc_id
  judgment_lb_sg_id = module.sg.judgment_lb_sg_id
  backend_target_group_arn = module.alb.judgment_target_group_arn
  websocket_target_group_arn = module.alb.websocket_server_target_group_1_arn
}

module ecs {
  source = "./ecs"
  subnet_ids = module.vpc.all_subnets
  backend_target_group_arn = module.alb.judgment_target_group_arn
  backend_target_group_id = module.alb.judgment_target_group_id
  websocket_target_group_arn = module.alb.websocket_server_target_group_1_arn
  websocket_target_group_id = module.alb.websocket_server_target_group_1_id
  judgment_ecs_sg_id = module.sg.judgment_ecs_sg_id
  async_eval_worker_sg_id = module.sg.async_eval_worker_id
  ecs_task_execution_role_arn = module.iam.ecs_task_execution_role_arn
  judgment_lb_id = module.alb.judgment_lb_id
  judgment_lb_arn = module.alb.judgment_lb_arn
  prod_api_keys_misc_version_arn = module.secretsmanager.prod_api_keys_misc_version_arn
  prod_api_keys_openai_version_arn = module.secretsmanager.prod_api_keys_openai_version_arn
  prod_creds_rabbitmq_version_arn = module.secretsmanager.prod_creds_rabbitmq_version_arn
}

module iam {
  source = "./iam"
  prod_api_keys_misc_arn = module.secretsmanager.prod_api_keys_misc_arn
  prod_api_keys_openai_arn = module.secretsmanager.prod_api_keys_openai_arn
  prod_creds_rabbitmq_arn = module.secretsmanager.prod_creds_rabbitmq_arn
  prod_api_keys_stripe_arn = module.secretsmanager.prod_api_keys_stripe_arn
}

module mq {
  source = "./mq"
}

module secretsmanager {
  source = "./secretsmanager"
  supabase_url = var.supabase_url
  supabase_anon_key = var.supabase_anon_key
  supabase_service_role_key = var.supabase_service_role_key
  supabase_jwt_secret = var.supabase_jwt_secret
  supabase_project_id = var.supabase_project_id
  rabbitmq_url = module.mq.aws_mq_broker_rabbitmq-judgment_url
  rabbitmq_broker_name = module.mq.aws_mq_broker_rabbitmq-judgment_name
  rabbitmq_broker_id = module.mq.aws_mq_broker_rabbitmq-judgment_id
  judgment_lb_dns_name = module.alb.judgment_lb_dns_name
  langfuse_public_key = var.langfuse_public_key
  langfuse_secret_key = var.langfuse_secret_key
  openai_api_key = var.openai_api_key
  togetherai_api_key = var.togetherai_api_key
  anthropic_api_key = var.anthropic_api_key
}

module sg {
  source = "./sg"
  judgment_vpc_id = module.vpc.aws_vpc_judgment_vpc_id
}

module vpc {
  source = "./vpc"
}