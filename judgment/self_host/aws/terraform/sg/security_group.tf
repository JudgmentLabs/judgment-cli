# resource "aws_security_group" "guardduty_managed" {
#   description = "Associated with VPC-vpc-051ded8ab85c23058 and tagged as GuardDutyManaged"

#   ingress {
#     cidr_blocks = ["172.31.0.0/16"]
#     description = "GuardDuty managed security group inbound rule associated with VPC vpc-051ded8ab85c23058"
#     from_port   = "443"
#     protocol    = "tcp"
#     self        = "false"
#     to_port     = "443"
#   }

#   name = "GuardDutyManagedSecurityGroup-vpc-051ded8ab85c23058"

#   tags = {
#     GuardDutyManaged = "true"
#   }

#   tags_all = {
#     GuardDutyManaged = "true"
#   }

#   vpc_id = "vpc-051ded8ab85c23058"
# }

# resource "aws_vpc_security_group_ingress_rule" "guardduty_managed_ingress" {
#   security_group_id = aws_security_group.guardduty_managed.id
#   cidr_ipv4         = "172.31.0.0/16"
#   description       = "GuardDuty managed security group inbound rule associated with VPC vpc-051ded8ab85c23058"
#   from_port         = 443
#   ip_protocol       = "tcp"
#   to_port           = 443
# }

# resource "aws_security_group" "rabbitmq_alb" {
#   description = "RabbitMQ ALB SG"

#   egress {
#     description     = "Route only directly to the RabbitMQ ECS Task"
#     from_port       = "0"
#     protocol        = "-1"
#     security_groups = ["${data.terraform_remote_state.sg.outputs.aws_security_group_tfer--rabbitmq-public-testing_sg-08b15a4a4d08d0512_id}"]
#     self            = "false"
#     to_port         = "0"
#   }

#   ingress {
#     cidr_blocks      = ["0.0.0.0/0"]
#     from_port        = "15672"
#     ipv6_cidr_blocks = ["::/0"]
#     protocol         = "tcp"
#     self             = "false"
#     to_port          = "15672"
#   }

#   ingress {
#     cidr_blocks      = ["0.0.0.0/0"]
#     from_port        = "5672"
#     ipv6_cidr_blocks = ["::/0"]
#     protocol         = "tcp"
#     self             = "false"
#     to_port          = "5672"
#   }

#   name   = "RabbitMQAlb-SG"
#   vpc_id = "vpc-051ded8ab85c23058"
# }

# resource "aws_vpc_security_group_egress_rule" "rabbitmq_alb_egress" {
#   security_group_id = aws_security_group.rabbitmq_alb.id
#   description       = "Route only directly to the RabbitMQ ECS Task"
#   from_port         = 0
#   ip_protocol       = "-1"
#   to_port           = 0
#   referenced_security_group_id = data.terraform_remote_state.sg.outputs.rabbitmq_public_id
# }

# resource "aws_vpc_security_group_ingress_rule" "rabbitmq_alb_ingress_15672" {
#   security_group_id = aws_security_group.rabbitmq_alb.id
#   cidr_ipv4         = "0.0.0.0/0"
#   cidr_ipv6         = "::/0"
#   from_port         = 15672
#   ip_protocol       = "tcp"
#   to_port           = 15672
# }

# resource "aws_vpc_security_group_ingress_rule" "rabbitmq_alb_ingress_5672" {
#   security_group_id = aws_security_group.rabbitmq_alb.id
#   cidr_ipv4         = "0.0.0.0/0"
#   cidr_ipv6         = "::/0"
#   from_port         = 5672
#   ip_protocol       = "tcp"
#   to_port           = 5672
# }

resource "aws_security_group" "async_eval_worker" {
  description = "Security group for Async Eval Worker"
  name        = "async-eval-worker-sg"
  vpc_id      = var.judgment_vpc_id
}

resource "aws_vpc_security_group_egress_rule" "async_eval_worker_egress" {
  security_group_id = aws_security_group.async_eval_worker.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# resource "aws_security_group" "default" {
#   description = "default VPC security group"
#   name        = "default"
#   vpc_id      = var.judgment_vpc_id
# }

# resource "aws_vpc_security_group_egress_rule" "default_egress" {
#   security_group_id = aws_security_group.default.id
#   cidr_ipv4         = "0.0.0.0/0"
#   from_port         = 0
#   ip_protocol       = "-1"
#   to_port           = 0
# }

# resource "aws_vpc_security_group_ingress_rule" "default_ingress_443" {
#   security_group_id = aws_security_group.default.id
#   cidr_ipv4         = "0.0.0.0/0"
#   from_port         = 443
#   ip_protocol       = "tcp"
#   to_port           = 443
# }

# resource "aws_vpc_security_group_ingress_rule" "default_ingress_443_ipv6" {
#   security_group_id = aws_security_group.default.id
#   cidr_ipv6         = "::/0"
#   from_port         = 443
#   ip_protocol       = "tcp"
#   to_port           = 443
# }

# resource "aws_vpc_security_group_ingress_rule" "default_ingress_80" {
#   security_group_id = aws_security_group.default.id
#   cidr_ipv4         = "0.0.0.0/0"
#   from_port         = 80
#   ip_protocol       = "tcp"
#   to_port           = 80
# }

# resource "aws_vpc_security_group_ingress_rule" "default_ingress_80_ipv6" {
#   security_group_id = aws_security_group.default.id
#   cidr_ipv6         = "::/0"
#   from_port         = 80
#   ip_protocol       = "tcp"
#   to_port           = 80
# }

# resource "aws_vpc_security_group_ingress_rule" "default_ingress_8001" {
#   security_group_id = aws_security_group.default.id
#   cidr_ipv4         = "0.0.0.0/0"
#   from_port         = 8001
#   ip_protocol       = "tcp"
#   to_port           = 8001
# }

# resource "aws_vpc_security_group_ingress_rule" "default_ingress_8001_ipv6" {
#   security_group_id = aws_security_group.default.id
#   cidr_ipv6         = "::/0"
#   from_port         = 8001
#   ip_protocol       = "tcp"
#   to_port           = 8001
# }

# resource "aws_vpc_security_group_ingress_rule" "default_ingress_8080" {
#   security_group_id = aws_security_group.default.id
#   cidr_ipv4         = "0.0.0.0/0"
#   from_port         = 8080
#   ip_protocol       = "tcp"
#   to_port           = 8080
# }

# resource "aws_vpc_security_group_ingress_rule" "default_ingress_8080_ipv6" {
#   security_group_id = aws_security_group.default.id
#   cidr_ipv6         = "::/0"
#   from_port         = 8080
#   ip_protocol       = "tcp"
#   to_port           = 8080
# }

resource "aws_security_group" "judgment_ecs_sg" {
  description = "Judgment ECS Service Security Group"
  name        = "judgment-ecs-service-sg"
  vpc_id      = var.judgment_vpc_id
}

resource "aws_vpc_security_group_egress_rule" "judgment_ecs_egress" {
  security_group_id = aws_security_group.judgment_ecs_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "judgment_ecs_ingress" {
  security_group_id = aws_security_group.judgment_ecs_sg.id
  from_port         = 0
  ip_protocol       = "tcp"
  to_port           = 65535
  referenced_security_group_id = aws_security_group.judgment_lb_sg.id
}

# resource "aws_security_group" "tfer--judgment-ecs-service-staging-sg_sg-004edfb405d44cc74" {
#   description = "prevent public ip access"

#   egress {
#     cidr_blocks = ["0.0.0.0/0"]
#     from_port   = "0"
#     protocol    = "-1"
#     self        = "false"
#     to_port     = "0"
#   }

#   ingress {
#     from_port       = "0"
#     protocol        = "tcp"
#     security_groups = ["${data.terraform_remote_state.sg.outputs.aws_security_group_tfer--judgment-staging-sg_sg-0b2591a49f5bcc6a8_id}"]
#     self            = "false"
#     to_port         = "65535"
#   }

#   name   = "judgment-ecs-service-staging-sg"
#   vpc_id = "vpc-051ded8ab85c23058"
# }

resource "aws_security_group" "judgment_lb_sg" {
  description = "Judgment Security Group"
  name        = "judgment-sg"
  vpc_id      = var.judgment_vpc_id
}

resource "aws_vpc_security_group_egress_rule" "judgment_lb_egress" {
  security_group_id = aws_security_group.judgment_lb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "judgment_lb_ingress_443" {
  security_group_id = aws_security_group.judgment_lb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "judgment_lb_ingress_443_ipv6" {
  security_group_id = aws_security_group.judgment_lb_sg.id
  cidr_ipv6         = "::/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}

resource "aws_vpc_security_group_ingress_rule" "judgment_lb_ingress_80" {
  security_group_id = aws_security_group.judgment_lb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "judgment_lb_ingress_80_ipv6" {
  security_group_id = aws_security_group.judgment_lb_sg.id
  cidr_ipv6         = "::/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "judgment_lb_ingress_8080" {
  security_group_id = aws_security_group.judgment_lb_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 8080
  ip_protocol       = "tcp"
  to_port           = 8080
}

resource "aws_vpc_security_group_ingress_rule" "judgment_lb_ingress_8080_ipv6" {
  security_group_id = aws_security_group.judgment_lb_sg.id
  cidr_ipv6         = "::/0"
  from_port         = 8080
  ip_protocol       = "tcp"
  to_port           = 8080
}

# resource "aws_security_group" "tfer--judgment-staging-sg_sg-0b2591a49f5bcc6a8" {
#   description = "Allow traffic to staging backend server"

#   egress {
#     cidr_blocks = ["0.0.0.0/0"]
#     from_port   = "0"
#     protocol    = "-1"
#     self        = "false"
#     to_port     = "0"
#   }

#   ingress {
#     cidr_blocks      = ["0.0.0.0/0"]
#     from_port        = "443"
#     ipv6_cidr_blocks = ["::/0"]
#     protocol         = "tcp"
#     self             = "false"
#     to_port          = "443"
#   }

#   ingress {
#     cidr_blocks      = ["0.0.0.0/0"]
#     from_port        = "80"
#     ipv6_cidr_blocks = ["::/0"]
#     protocol         = "tcp"
#     self             = "false"
#     to_port          = "80"
#   }

#   ingress {
#     cidr_blocks      = ["0.0.0.0/0"]
#     from_port        = "8080"
#     ipv6_cidr_blocks = ["::/0"]
#     protocol         = "tcp"
#     self             = "false"
#     to_port          = "8080"
#   }

#   name   = "judgment-staging-sg"
#   vpc_id = "vpc-051ded8ab85c23058"
# }

# resource "aws_security_group" "tfer--launch-wizard-1_sg-0cde058f6f954380a" {
#   description = "launch-wizard-1 created 2025-04-03T19:18:39.610Z"

#   egress {
#     cidr_blocks      = ["0.0.0.0/0"]
#     from_port        = "0"
#     ipv6_cidr_blocks = ["::/0"]
#     protocol         = "-1"
#     self             = "false"
#     to_port          = "0"
#   }

#   ingress {
#     cidr_blocks = ["0.0.0.0/0"]
#     from_port   = "22"
#     protocol    = "tcp"
#     self        = "false"
#     to_port     = "22"
#   }

#   ingress {
#     cidr_blocks      = ["0.0.0.0/0"]
#     from_port        = "8000"
#     ipv6_cidr_blocks = ["::/0"]
#     protocol         = "tcp"
#     self             = "false"
#     to_port          = "8000"
#   }

#   name   = "launch-wizard-1"
#   vpc_id = "vpc-051ded8ab85c23058"
# }

# resource "aws_security_group" "tfer--rabbitmq-public-testing_sg-08b15a4a4d08d0512" {
#   description = "[REMOVE ONCE DONE TESTING RABBITMQ] Makes queue publicly available"

#   egress {
#     cidr_blocks = ["0.0.0.0/0"]
#     from_port   = "0"
#     protocol    = "-1"
#     self        = "false"
#     to_port     = "0"
#   }

#   ingress {
#     cidr_blocks      = ["0.0.0.0/0"]
#     from_port        = "5672"
#     ipv6_cidr_blocks = ["::/0"]
#     protocol         = "tcp"
#     security_groups  = ["${data.terraform_remote_state.sg.outputs.aws_security_group_tfer--default_sg-0f7d949b62cddb276_id}"]
#     self             = "false"
#     to_port          = "5672"
#   }

#   ingress {
#     description     = "RabbitMQ Public ALB"
#     from_port       = "0"
#     protocol        = "tcp"
#     security_groups = ["${data.terraform_remote_state.sg.outputs.aws_security_group_tfer--RabbitMQAlb-SG_sg-0260fd52db8edca8a_id}"]
#     self            = "false"
#     to_port         = "65535"
#   }

#   name   = "rabbitmq-public-testing"
#   vpc_id = "vpc-051ded8ab85c23058"
# }

# resource "aws_vpc_security_group_ingress_rule" "rabbitmq_public_ingress_5672" {
#   security_group_id = aws_security_group.rabbitmq_public.id
#   cidr_ipv4         = "0.0.0.0/0"
#   cidr_ipv6         = "::/0"
#   from_port         = 5672
#   ip_protocol       = "tcp"
#   to_port           = 5672
#   referenced_security_group_id = data.terraform_remote_state.sg.outputs.default_id
# }

# resource "aws_vpc_security_group_ingress_rule" "rabbitmq_public_ingress_alb" {
#   security_group_id = aws_security_group.rabbitmq_public.id
#   description       = "RabbitMQ Public ALB"
#   from_port         = 0
#   ip_protocol       = "tcp"
#   to_port           = 65535
#   referenced_security_group_id = data.terraform_remote_state.sg.outputs.rabbitmq_alb_id
# }

# resource "aws_security_group" "tfer--security-group-for-inbound-nfs-d-xffh5k2o2bqf_sg-0717253136c6d0900" {
#   description = "[DO NOT DELETE] Security Group that allows inbound NFS traffic for SageMaker Notebooks Domain [d-xffh5k2o2bqf]"

#   ingress {
#     from_port       = "1018"
#     protocol        = "tcp"
#     security_groups = ["${data.terraform_remote_state.sg.outputs.aws_security_group_tfer--security-group-for-outbound-nfs-d-xffh5k2o2bqf_sg-0342662619f0baf23_id}"]
#     self            = "false"
#     to_port         = "1023"
#   }

#   ingress {
#     from_port       = "2049"
#     protocol        = "tcp"
#     security_groups = ["${data.terraform_remote_state.sg.outputs.aws_security_group_tfer--security-group-for-outbound-nfs-d-xffh5k2o2bqf_sg-0342662619f0baf23_id}"]
#     self            = "false"
#     to_port         = "2049"
#   }

#   ingress {
#     from_port       = "988"
#     protocol        = "tcp"
#     security_groups = ["${data.terraform_remote_state.sg.outputs.aws_security_group_tfer--security-group-for-outbound-nfs-d-xffh5k2o2bqf_sg-0342662619f0baf23_id}"]
#     self            = "false"
#     to_port         = "988"
#   }

#   name = "security-group-for-inbound-nfs-d-xffh5k2o2bqf"

#   tags = {
#     ManagedByAmazonSageMakerResource = "arn:aws:sagemaker:us-west-1:585008087243:domain/d-xffh5k2o2bqf"
#   }

#   tags_all = {
#     ManagedByAmazonSageMakerResource = "arn:aws:sagemaker:us-west-1:585008087243:domain/d-xffh5k2o2bqf"
#   }

#   vpc_id = "vpc-051ded8ab85c23058"
# }

# resource "aws_security_group" "tfer--security-group-for-outbound-nfs-d-xffh5k2o2bqf_sg-0342662619f0baf23" {
#   description = "[DO NOT DELETE] Security Group that allows outbound NFS traffic for SageMaker Notebooks Domain [d-xffh5k2o2bqf]"

#   egress {
#     from_port       = "1018"
#     protocol        = "tcp"
#     security_groups = ["${data.terraform_remote_state.sg.outputs.aws_security_group_tfer--security-group-for-inbound-nfs-d-xffh5k2o2bqf_sg-0717253136c6d0900_id}"]
#     self            = "false"
#     to_port         = "1023"
#   }

#   egress {
#     from_port       = "2049"
#     protocol        = "tcp"
#     security_groups = ["${data.terraform_remote_state.sg.outputs.aws_security_group_tfer--security-group-for-inbound-nfs-d-xffh5k2o2bqf_sg-0717253136c6d0900_id}"]
#     self            = "false"
#     to_port         = "2049"
#   }

#   egress {
#     from_port       = "988"
#     protocol        = "tcp"
#     security_groups = ["${data.terraform_remote_state.sg.outputs.aws_security_group_tfer--security-group-for-inbound-nfs-d-xffh5k2o2bqf_sg-0717253136c6d0900_id}"]
#     self            = "false"
#     to_port         = "988"
#   }

#   name = "security-group-for-outbound-nfs-d-xffh5k2o2bqf"

#   tags = {
#     ManagedByAmazonSageMakerResource = "arn:aws:sagemaker:us-west-1:585008087243:domain/d-xffh5k2o2bqf"
#   }

#   tags_all = {
#     ManagedByAmazonSageMakerResource = "arn:aws:sagemaker:us-west-1:585008087243:domain/d-xffh5k2o2bqf"
#   }

#   vpc_id = "vpc-051ded8ab85c23058"
# }

resource "aws_security_group" "websockets_ecs_sg" {
  description = "WebSocket ECS Service Security Group"
  name        = "websockets-ecs-service-sg"
  vpc_id      = var.judgment_vpc_id
}

resource "aws_vpc_security_group_egress_rule" "websockets_ecs_egress" {
  security_group_id = aws_security_group.websockets_ecs_sg.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "websockets_ecs_ingress" {
  security_group_id = aws_security_group.websockets_ecs_sg.id
  from_port         = 0
  ip_protocol       = "tcp"
  to_port           = 65535
  referenced_security_group_id = aws_security_group.judgment_lb_sg.id
}
